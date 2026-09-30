import hxunity.yaml.*;
class Probe4 {
  static function main() {
    var text = [
      "GameObject:",
      "  m_Component:",
      "  - component: {fileID: 1}",
      "  - component: {fileID: 2}",
      "  - ",
      "  m_Other: 5",
      "  m_Scalars:",
      "  - one",
      "  - two",
      "  m_Empty: []"
    ].join("\n") + "\n";
    var root = YamlParser.parse(text);
    var g = root.asMap().getMap("GameObject");
    for (e in g.entries) {
      var t = Type.getClassName(Type.getClass(e.value));
      Sys.println(e.key + " -> " + t + " isSeq=" + Std.isOfType(e.value, YamlSeq));
      if (Std.isOfType(e.value, YamlSeq)) { var s:YamlSeq = cast e.value; Sys.println("    items=" + s.items.length + " flow=" + s.flow); }
    }
    Sys.println("--- tokens ---");
    var lx = new YamlLexer(text);
    while (true) { var tk = lx.next(); if (tk.type == Eof) break; Sys.println(tk.line + " " + tk.type + " '" + tk.text + "' col=" + tk.column + " ind=" + tk.indent); }
  }
}
// scratch
