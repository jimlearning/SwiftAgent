import Foundation

// MARK: - NotebookEditTool

/// Edits cells in Jupyter notebook (.ipynb) files.
/// Matches Claude Code's NotebookEditTool.
public struct NotebookEditTool: Tool {
    public let name = "NotebookEdit"
    public var searchHint: String? { "edit Jupyter notebook cells (.ipynb)" }
    public func description(input: [String: JSONValue], options: ToolDescriptionOptions) async -> String { "Edit Jupyter notebook cells (.ipynb)" }
    public let isReadOnly = false
    public let isConcurrencySafe = false
    public var shouldDefer: Bool { true }
    public let inputSchema: JSONSchema = {
        var schema = JSONSchema(type: "object", properties: [:])
        schema.properties?["notebookPath"] = JSONSchemaProperty(type: "string", description: "The absolute path to the Jupyter notebook file to edit (must be absolute, not relative)")
        schema.properties?["cellId"] = JSONSchemaProperty(type: "string", description: "The ID of the cell to edit. When inserting a new cell, the new cell will be inserted after the cell with this ID, or at the beginning if not specified.")
        schema.properties?["newSource"] = JSONSchemaProperty(type: "string", description: "The new source for the cell")
        schema.properties?["cellType"] = JSONSchemaProperty(type: "string", description: "The type of the cell (code or markdown). If not specified, defaults to current cell type. Required for editMode=insert.", enum: ["code", "markdown"])
        schema.properties?["editMode"] = JSONSchemaProperty(type: "string", description: "The type of edit to make (replace, insert, delete). Defaults to replace.", enum: ["replace", "insert", "delete"])
        schema.required = ["notebookPath", "newSource"]
        return schema
    }()

    public init() {}

    public func call(input: [String: JSONValue], context: ToolUseContext, canUseTool: CanUseToolFn? = nil, parentMessage: Message? = nil, onProgress: ToolCallProgress? = nil) async throws -> ToolResult {
        // Parse inputs
        guard let pathVal = input["notebookPath"], case .string(let notebookPath) = pathVal else {
            return ToolResult(content: "Error: notebookPath is required", isError: true)
        }

        guard let sourceVal = input["newSource"], case .string(let newSource) = sourceVal else {
            return ToolResult(content: "Error: newSource is required", isError: true)
        }

        let cellId: String?
        if let c = input["cellId"], case .string(let s) = c { cellId = s } else { cellId = nil }

        let cellType: String
        if let c = input["cellType"], case .string(let s) = c { cellType = s } else { cellType = "code" }

        let editMode: String
        if let e = input["editMode"], case .string(let s) = e { editMode = s } else { editMode = "replace" }

        // Validate path has .ipynb extension
        guard notebookPath.hasSuffix(".ipynb") else {
            return ToolResult(content: "File must be a Jupyter notebook (.ipynb file). For editing other file types, use the Edit tool.", isError: true)
        }

        // Validate edit_mode
        guard ["replace", "insert", "delete"].contains(editMode) else {
            return ToolResult(content: "Edit mode must be replace, insert, or delete.", isError: true)
        }

        if editMode == "insert" && cellType.isEmpty {
            return ToolResult(content: "Cell type is required when using edit_mode=insert.", isError: true)
        }

        // Read notebook file
        let fileURL = URL(fileURLWithPath: notebookPath)
        guard FileManager.default.fileExists(atPath: notebookPath) else {
            return ToolResult(content: "Notebook file does not exist.", isError: true)
        }

        let originalContent: String
        do {
            originalContent = try String(contentsOf: fileURL, encoding: .utf8)
        } catch {
            return ToolResult(content: "Failed to read notebook: \(error.localizedDescription)", isError: true)
        }

        // Parse as JSON
        guard let data = originalContent.data(using: .utf8),
              var notebook = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              var cells = notebook["cells"] as? [[String: Any]] else {
            return ToolResult(content: "Notebook is not valid JSON.", isError: true)
        }

        let nbformat = notebook["nbformat"] as? Int ?? 4
        let nbformatMinor = notebook["nbformat_minor"] as? Int ?? 0

        // Find cell index
        var cellIndex: Int
        if let cellId = cellId {
            // Try to find by ID
            var found = false
            var idIndex = -1
            for (i, cell) in cells.enumerated() {
                if let id = cell["id"] as? String, id == cellId {
                    idIndex = i
                    found = true
                    break
                }
            }
            if found {
                cellIndex = idIndex
            } else {
                // Try cell-N format
                let parsed = parseCellId(cellId)
                if let idx = parsed, idx < cells.count {
                    cellIndex = idx
                } else if parsed != nil {
                    return ToolResult(content: "Cell with index \(parsed!) does not exist in notebook.", isError: true)
                } else {
                    return ToolResult(content: "Cell with ID \"\(cellId)\" not found in notebook.", isError: true)
                }
            }

            if editMode == "insert" {
                cellIndex += 1 // Insert after the cell
            }
        } else if editMode == "insert" {
            cellIndex = 0 // Insert at beginning
        } else {
            return ToolResult(content: "Cell ID must be specified when not inserting a new cell.", isError: true)
        }

        // Convert replace to insert if at end
        var resolvedEditMode = editMode
        if resolvedEditMode == "replace" && cellIndex == cells.count {
            resolvedEditMode = "insert"
        }

        // Generate new cell ID if needed
        let needId = nbformat > 4 || (nbformat == 4 && nbformatMinor >= 5)
        var newCellId: String?

        // Perform the edit
        switch resolvedEditMode {
        case "delete":
            guard cellIndex < cells.count else {
                return ToolResult(content: "Cell index out of range.", isError: true)
            }
            cells.remove(at: cellIndex)

        case "insert":
            if needId { newCellId = randomCellId() }
            var newCell: [String: Any] = [
                "cell_type": cellType,
                "source": newSource,
                "metadata": [String: Any]()
            ]
            if let id = newCellId { newCell["id"] = id }
            if cellType == "code" {
                newCell["execution_count"] = NSNull()
                newCell["outputs"] = [Any]()
            }
            if cellIndex > cells.count { cellIndex = cells.count }
            cells.insert(newCell, at: cellIndex)

        case "replace":
            guard cellIndex < cells.count else {
                return ToolResult(content: "Cell index out of range.", isError: true)
            }
            var targetCell = cells[cellIndex]
            targetCell["source"] = newSource
            if cellType != (targetCell["cell_type"] as? String ?? "code") {
                targetCell["cell_type"] = cellType
            }
            if targetCell["cell_type"] as? String == "code" {
                targetCell["execution_count"] = NSNull()
                targetCell["outputs"] = [Any]()
            }
            if needId, targetCell["id"] == nil {
                targetCell["id"] = randomCellId()
            }
            cells[cellIndex] = targetCell

        default:
            break
        }

        // Update notebook
        notebook["cells"] = cells

        // Write back
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: notebook, options: [.prettyPrinted, .sortedKeys])
            try jsonData.write(to: fileURL)
        } catch {
            return ToolResult(content: "Failed to write notebook: \(error.localizedDescription)", isError: true)
        }

        // Build result message
        let resultCellId = newCellId ?? cellId ?? "0"
        switch resolvedEditMode {
        case "replace":
            return ToolResult(content: "Updated cell \(resultCellId) with \(newSource)")
        case "insert":
            return ToolResult(content: "Inserted cell \(resultCellId) with \(newSource)")
        case "delete":
            return ToolResult(content: "Deleted cell \(resultCellId)")
        default:
            return ToolResult(content: "Unknown edit mode")
        }
    }
}

/// Parse cell-N format into numeric index.
private func parseCellId(_ cellId: String) -> Int? {
    guard cellId.hasPrefix("cell-") else { return nil }
    let numStr = String(cellId.dropFirst(5))
    return Int(numStr)
}

/// Generate a random cell ID string.
private func randomCellId() -> String {
    let chars = "abcdefghijklmnopqrstuvwxyz0123456789"
    return String((0..<13).map { _ in chars.randomElement()! })
}
