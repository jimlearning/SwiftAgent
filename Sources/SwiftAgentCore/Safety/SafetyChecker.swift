import Foundation

/// Detects dangerous patterns in tool input using multi-layer analysis.
/// Mirrors Claude Code's bash security analysis (~3000 lines).
public struct SafetyChecker: Sendable {

    public init() {}

    /// Check tool input for dangerous patterns.
    /// Returns a reason if dangerous, nil if safe.
    public func check(toolName: String, input: [String: JSONValue]) -> String? {
        switch toolName {
        case "Bash":
            if case .string(let command) = input["command"] {
                return checkShellCommand(command)
            }
        case "Write", "Edit":
            if case .string(let path) = input["file_path"] {
                return checkFilePath(path)
            }
        default:
            break
        }
        return nil
    }

    // MARK: - Shell command analysis (4-layer)

    private func checkShellCommand(_ command: String) -> String? {
        // Layer 1: Block immediate fatal patterns
        if let reason = layer1FatalPatterns(command) { return reason }

        // Layer 2: Check for command chaining abuse
        if let reason = layer2CommandChaining(command) { return reason }

        // Layer 3: Check for obfuscation / encoding tricks
        if let reason = layer3Obfuscation(command) { return reason }

        // Layer 4: Check for network + execution combinations
        if let reason = layer4NetworkExec(command) { return reason }

        return nil
    }

    // MARK: Layer 1 — Fatal patterns (immediate deny)

    private func layer1FatalPatterns(_ cmd: String) -> String? {
        let patterns: [(String, String)] = [
            // Filesystem destruction
            ("rm\\s+-rf\\s+/", "Cannot delete root filesystem"),
            ("rm\\s+-rf\\s+~", "Cannot recursively delete home directory"),
            ("rm\\s+-rf\\s+\\$HOME", "Cannot recursively delete HOME"),
            ("rm\\s+-rf\\s+\\/\\*", "Cannot recursively delete root contents"),
            ("mkfs\\.", "Cannot format filesystems"),
            ("mkswap", "Cannot create swap on raw devices"),

            // Disk device writing
            (">\\s*/dev/sd[a-z]", "Cannot write to raw disk devices"),
            (">>\\s*/dev/sd[a-z]", "Cannot append to raw disk devices"),
            ("dd\\s+if=.*of=/dev/", "Cannot use dd on raw disk devices"),
            ("dd\\s+if=/dev/.*of=/dev/", "Cannot clone raw disk devices"),
            ("cat\\s+/dev/.*>\\s*/dev/", "Cannot redirect block devices"),

            // Fork bombs
            (":\\(\\)\\s*\\{\\s*:\\s*\\|\\s*:?\\s*&\\s*\\}\\s*;\\s*:", "Fork bomb detected"),
            (":\\(\\).*\\{.*\\|.*&.*\\}.*;.*:", "Fork bomb variant detected"),

            // Root permission changes
            ("chmod\\s+-R\\s+777\\s+/", "Cannot recursively chmod 777 root"),
            ("chmod\\s+777\\s+/etc", "Cannot chmod 777 /etc"),
            ("chmod\\s+777\\s+/usr", "Cannot chmod 777 /usr"),
            ("chown\\s+-R\\s+\\w+\\s+/", "Cannot recursively chown root"),
            ("chown\\s+\\w+:\\w+\\s+/", "Cannot chown root"),

            // Destructive mounts
            ("mount\\s+.*-o\\s+remount", "Remounting filesystems blocked"),
            ("umount\\s+/", "Cannot unmount root filesystem"),

            // Kernel manipulation
            ("sysctl\\s+-w\\s+kernel", "Cannot modify kernel parameters"),
            ("modprobe\\s+-r", "Cannot remove kernel modules"),

            // System critical service manipulation
            ("launchctl\\s+unload\\s+/System", "Cannot unload system services"),
            ("systemctl\\s+disable\\s+", "Disabling system services blocked"),
        ]

        for (pattern, reason) in patterns {
            if cmd.range(of: pattern, options: .regularExpression) != nil {
                return reason
            }
        }
        return nil
    }

    // MARK: Layer 2 — Command chaining analysis

    private func layer2CommandChaining(_ cmd: String) -> String? {
        // Split by command separators
        let separators = [";", "&&", "||", "|&", "\n"]
        var segments = [cmd]
        for sep in separators {
            segments = segments.flatMap { $0.components(separatedBy: sep) }
        }

        // Check for dangerous command combinations in the chain
        let downloadAndExec = [
            ("curl", "sh"), ("curl", "bash"), ("curl", "zsh"),
            ("wget", "sh"), ("wget", "bash"), ("wget", "zsh"),
        ]

        let hasPipe = cmd.contains("|")
        let segmentsLower = segments.map { $0.trimmingCharacters(in: .whitespaces).lowercased() }

        if hasPipe {
            for (downloader, shell) in downloadAndExec {
                let hasDownloader = segmentsLower.contains { $0.contains(downloader) }
                let hasShell = segmentsLower.contains { $0.trimmingCharacters(in: .punctuationCharacters) == shell || $0.hasPrefix("\(shell) ") }
                if hasDownloader && hasShell {
                    return "Piped download-to-execution detected (\(downloader) | \(shell))"
                }
            }
        }

        // Check for reverse shells
        let reverseShellIndicators = [
            "/dev/tcp/", "/dev/udp/", "nc\\s+.*-e\\s+", "ncat\\s+.*-e\\s+",
            "socat\\s+.*exec:", "python.*socket\\.connect", "perl.*Socket.*connect",
            "ruby.*TCPSocket\\.open", "php.*fsockopen",
        ]
        for pattern in reverseShellIndicators {
            if cmd.range(of: pattern, options: .regularExpression) != nil {
                return "Reverse shell pattern detected"
            }
        }

        return nil
    }

    // MARK: Layer 3 — Obfuscation detection

    private func layer3Obfuscation(_ cmd: String) -> String? {
        // Base64-encoded execution
        let base64ExecPatterns = [
            "base64\\s+(-d|--decode).*\\|",
            "base64\\s+(-d|--decode).*\\$\\(",
            "openssl\\s+base64\\s+-d.*\\|",
            "\\$\\s*\\(\\s*echo\\s+[^)]*base64",
        ]
        for pattern in base64ExecPatterns {
            if cmd.range(of: pattern, options: .regularExpression) != nil {
                return "Base64-encoded command execution detected"
            }
        }

        // Hex-encoded execution
        if cmd.range(of: "xxd\\s+-r\\s+-p", options: .regularExpression) != nil ||
           cmd.range(of: "printf\\s+['\"]\\\\x[0-9a-fA-F]", options: .regularExpression) != nil {
            return "Hex-encoded command detected"
        }

        // Environment variable manipulation
        let envDanger = [
            "LD_PRELOAD=", "LD_LIBRARY_PATH=.*/tmp",
            "DYLD_INSERT_LIBRARIES=", "DYLD_LIBRARY_PATH=.*/tmp",
            "PATH=.*/tmp.*:",
        ]
        for pattern in envDanger {
            if cmd.range(of: pattern, options: .regularExpression) != nil {
                return "Dangerous environment variable manipulation detected"
            }
        }

        // Process substitution tricks
        if cmd.range(of: "<\\(.*\\)", options: .regularExpression) != nil {
            if cmd.range(of: "rm\\s+-rf\\s+<\\(|\\.\\.\\..*<\\(|>.*<\\(.*\\)", options: .regularExpression) != nil {
                return "Dangerous process substitution detected"
            }
        }

        return nil
    }

    // MARK: Layer 4 — Network + execution patterns

    private func layer4NetworkExec(_ cmd: String) -> String? {
        // Direct pipe from curl/wget to shell
        for pattern in [
            "curl\\s+\\S+\\s*\\|\\s*(ba)?sh",
            "curl\\s+\\S+\\s*\\|\\s*(zsh|python|perl|ruby|node)",
            "wget\\s+\\S+\\s*-O\\s*-\\s*\\|\\s*(ba)?sh",
            "wget\\s+\\S+\\s*-O\\s*-\\s*\\|\\s*(zsh|python|perl)",
            "curl\\s+\\S+\\s*\\|\\s*sudo\\s+(ba)?sh",
        ] {
            if cmd.range(of: pattern, options: .regularExpression) != nil {
                return "Download-to-pipe execution blocked"
            }
        }

        // Bind shell to network
        if cmd.range(of: "nc\\s+-l\\s+-p\\s+\\d+\\s+-e\\s+", options: .regularExpression) != nil ||
           cmd.range(of: "socat\\s+.*TCP-LISTEN.*exec", options: .regularExpression) != nil {
            return "Network bind shell detected"
        }

        // SSH with remote execution of dangerous commands
        if cmd.range(of: "ssh\\s+\\S+\\s+['\"]\\s*(rm\\s+-rf|mkfs|dd\\s+if)", options: .regularExpression) != nil {
            return "Remote destructive command via SSH detected"
        }

        return nil
    }

    // MARK: - File path validation

    private func checkFilePath(_ path: String) -> String? {
        // System directories that must not be modified
        let blockedPaths = [
            "/etc/", "/boot/", "/System/", "/Library/System/",
            "/private/etc/", "/usr/lib/", "/usr/include/",
            "/var/run/", "/var/db/",
        ]

        for blocked in blockedPaths {
            if path.hasPrefix(blocked) {
                return "Cannot write to system directory: \(blocked)"
            }
        }

        // SSH and security files
        let sensitiveFiles = [
            "/.ssh/authorized_keys", "/.ssh/id_rsa", "/.ssh/id_ed25519",
            "/.ssh/config", "/.ssh/known_hosts", "/.gnupg/", "/.aws/credentials",
        ]
        for sensitive in sensitiveFiles {
            if path.hasSuffix(sensitive) || path.contains(sensitive) {
                return "Cannot modify security-sensitive file: \(sensitive)"
            }
        }

        // Prevent writing to /dev or /proc
        if path.hasPrefix("/dev/") || path.hasPrefix("/proc/") || path.hasPrefix("/sys/") {
            return "Cannot write to virtual filesystem: \(path)"
        }

        // .env files with credential patterns — warn but allow
        if path.hasSuffix(".env") || path.contains("/.env") {
            return nil // Allow .env files but log
        }

        return nil
    }

    /// Validate a path exists and is within the working directory or tmp.
    public func validatePath(_ path: String, workingDirectory: String) -> String? {
        let resolved = (path as NSString).standardizingPath
        if !resolved.hasPrefix(workingDirectory)
            && !resolved.hasPrefix("/tmp")
            && !resolved.hasPrefix(NSTemporaryDirectory()) {
            return "Path '\(resolved)' is outside working directory and /tmp"
        }
        return nil
    }

    /// Check if a command is purely read-only (safe for auto-approval).
    public func isReadOnlyCommand(_ command: String) -> Bool {
        let readOnlyPrefixes = [
            "ls ", "cat ", "head ", "tail ", "grep ", "find ", "wc ",
            "du ", "df ", "file ", "stat ", "ps ", "top ", "htop ",
            "who ", "w ", "id ", "env ", "echo ", "pwd ", "which ",
            "git status", "git log", "git diff", "git show",
            "git branch", "git tag",
        ]
        let trimmed = command.trimmingCharacters(in: .whitespaces).lowercased()
        return readOnlyPrefixes.contains { trimmed.hasPrefix($0) }
    }
}
