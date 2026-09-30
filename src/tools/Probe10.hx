import hxunity.yaml.*;
class Probe10 {
  static function main() {
    var text = [
      "PrefabInstance:",
      "  m_Modification:",
      "    m_Modifications:",
      "    - target: {fileID: 1, guid: abc, type: 3}",
      "      propertyPath: m_Name",
      "      value: bananas",
      "    m_RemovedComponents: []",
      "  m_SourcePrefab: {fileID: 100100000, guid: abc, type: 3}"
    ].join("\n") + "\n";
    var lx = new YamlLexer(text);
    while (true) { var tk = lx.next(); if (tk.type == Eof) break; Sys.println("L" + tk.line + " ind=" + tk.indent + " col=" + tk.column + " " + tk.type + " '" + tk.text + "'"); }
  }
}
