import hxunity.yaml.*;
class Probe3 {
  static function main() {
    var text = "GameObject:\n  m_Empty: []\n  m_Comp:\n  - component: {fileID: 1}\n  m_Other: 5\n";
    var root = YamlParser.parse(text);
    var g = root.asMap().getMap("GameObject");
    for (e in g.entries) {
      var t = Type.getClassName(Type.getClass(e.value));
      Sys.println(e.key + " -> " + t + " null=" + (e.value == null));
      if (Std.isOfType(e.value, YamlSeq)) { var s:YamlSeq = cast e.value; Sys.println("    items=" + s.items.length + " flow=" + s.flow); }
      if (Std.isOfType(e.value, YamlMap)) { var m:YamlMap = cast e.value; Sys.println("    size=" + m.size()); }
    }
    Sys.println("--- tokens ---");
    var lx = new YamlLexer(text);
    while (true) { var tk = lx.next(); if (tk.type == Eof) break; Sys.println(tk.line + " " + tk.type + " '" + tk.text + "' col=" + tk.column + " ind=" + tk.indent); }
  }
}
