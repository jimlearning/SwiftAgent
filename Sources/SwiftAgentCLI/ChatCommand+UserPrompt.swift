import Foundation
import Darwin
import SwiftAgentCore

// MARK: - Interactive user question prompt

/// Prompt the user with multiple-choice questions interactively.
/// Used by AskUserQuestionTool via the userInputPromptHandler callback.
/// Fully restores the original terminal state (saved before LineEditor entered
/// raw mode) so that readLine() works correctly with proper line editing.
func promptUserForQuestions(_ questions: [UserQuestion], originalTermios: inout termios) async -> [UserQuestionResponse] {
    var responses: [UserQuestionResponse] = []
    var savedTermios = termios()
    let fd = STDIN_FILENO

    writeToStdout("\r\u{001B}[K")

    tcgetattr(fd, &savedTermios)
    tcsetattr(fd, TCSADRAIN, &originalTermios)
    defer {
        tcsetattr(fd, TCSADRAIN, &savedTermios)
    }

    for question in questions {
        if !question.header.isEmpty {
            writeToStdout("\n\u{001B}[1;36m── \(question.header) ──\u{001B}[0m\n")
        } else {
            writeToStdout("\n")
        }

        writeToStdout("\u{001B}[1;97m\(question.question)\u{001B}[0m\n\n")

        for (j, opt) in question.options.enumerated() {
            let letter = Character(UnicodeScalar(97 + j)!)
            writeToStdout("  \u{001B}[1;33m\(letter))\u{001B}[0m \u{001B}[1;97m\(opt.label)\u{001B}[0m")
            if let desc = opt.description, !desc.isEmpty {
                writeToStdout(" — \(desc)")
            }
            writeToStdout("\n")
        }

        if question.multiSelect {
            writeToStdout("\n  \u{001B}[2mEnter your choices (comma-separated, e.g. a-\(Character(UnicodeScalar(96 + question.options.count)!))): \u{001B}[0m")
        } else {
            writeToStdout("\n  \u{001B}[2mYour choice (a-\(Character(UnicodeScalar(96 + question.options.count)!))): \u{001B}[0m")
        }

        guard let line = Swift.readLine() else {
            responses.append(UserQuestionResponse(optionIndices: []))
            continue
        }

        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if question.multiSelect {
            let parts = trimmed.components(separatedBy: CharacterSet(charactersIn: ", "))
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }

            var indices: [Int] = []
            for part in parts {
                if part.count == 1 {
                    let letterChar = Character(part)
                    if let ascii = letterChar.asciiValue {
                        let idx = Int(ascii) - 97
                        if idx >= 0 && idx < question.options.count && !indices.contains(idx) {
                            indices.append(idx)
                        }
                    }
                } else {
                    if let matchIdx = question.options.firstIndex(where: {
                        $0.label.lowercased() == part
                    }) {
                        if !indices.contains(matchIdx) {
                            indices.append(matchIdx)
                        }
                    }
                }
            }
            indices.sort()
            if indices.isEmpty && !trimmed.isEmpty {
                responses.append(UserQuestionResponse(optionIndices: [], customText: line.trimmingCharacters(in: .whitespacesAndNewlines)))
            } else {
                responses.append(UserQuestionResponse(optionIndices: indices))
            }
        } else {
            if trimmed.count == 1 {
                let letterChar = Character(trimmed)
                if let ascii = letterChar.asciiValue {
                    let idx = Int(ascii) - 97
                    if idx >= 0 && idx < question.options.count {
                        responses.append(UserQuestionResponse(optionIndices: [idx]))
                        continue
                    }
                }
            }
            if let matchIdx = question.options.firstIndex(where: {
                $0.label.lowercased() == trimmed
            }) {
                responses.append(UserQuestionResponse(optionIndices: [matchIdx]))
            } else {
                responses.append(UserQuestionResponse(optionIndices: [], customText: line.trimmingCharacters(in: .whitespacesAndNewlines)))
            }
        }
    }

    return responses
}
