import hxunity.yaml.*;
class Probe13 {
  static function main() {
    var root = YamlParser.parse("a: plain\nb: 'single'\nc: \"double\"\nd: 'it''s escaped'\ne: \"tab\\there\"\nf: 'true'\n");
    var map = root.asMap();
    for (k in ["a","b","c","d","e","f"]) {
      var n = map.get(k);
      Sys.println(k + " class=" + Type.getClassName(Type.getClass(n)) + " isScalar=" + Std.isOfType(n, YamlScalar) + " str=" + n.toString() + " isNull=" + n.isNull());
    }
    Sys.println("--- writer ---");
    var m = new YamlMap();
    m.set("plain", new YamlScalar("hero", ScalarKind.Plain));
    m.set("keyword", new YamlScalar("yes", ScalarKind.Plain));
    m.set("number", new YamlScalar("10", ScalarKind.Plain));
    m.set("negative", new YamlScalar("-0.02", ScalarKind.Plain));
    m.set("empty", new YamlScalar("", ScalarKind.Plain));
    m.set("quoted", new YamlScalar("kept", ScalarKind.SingleQuoted));
    m.set("ref", hxunity.unity.UnityReference.none().toNode());
    var text = YamlWriter.write(m);
    for (line in text.split("\n")) Sys.println("|" + line + "|");
  }
}
