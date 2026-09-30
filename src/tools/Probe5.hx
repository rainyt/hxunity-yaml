import hxunity.yaml.*;
class Probe5 {
  static function main() {
    var text = [
      "GameObject:",
      "  m_Scalars:",
      "  - one",
      "  - two",
      "  m_Empty: []"
    ].join("\n") + "\n";
    var root = YamlParser.parse(text);
    var g = root.asMap().getMap("GameObject");
    Sys.println("keys=" + g.entries.length);
    for (e in g.entries) Sys.println("  key=" + e.key + " type=" + Type.getClassName(Type.getClass(e.value)));
    Sys.println("getSeq(m_Empty)=" + g.getSeq("m_Empty"));
    var s = g.getSeq("m_Scalars");
    Sys.println("m_Scalars items=" + s.items.length + " strs=" + s.toStrings().join(","));
  }
}
