import hxunity.yaml.YamlParser;
import hxunity.yaml.YamlMap;
import hxunity.yaml.YamlScalar;
class Probe2 {
  static function main() {
    var text = sys.io.File.getContent(Sys.args()[0]);
    var docs = YamlParser.parseAll(text);
    var d = docs[0];
    var body:hxunity.yaml.YamlMap = cast d.body;
    var mb = body.getMap("MonoBehaviour");
    if (mb == null) { Sys.println("no MonoBehaviour"); for (e in body.entries) Sys.println("key=" + e.key); return; }
    var s = mb.getString("_serializedGraph");
    Sys.println("length=" + s.length);
    var i = s.indexOf("\n");
    Sys.println("firstNewlineAt=" + i);
    if (i >= 0) {
      Sys.println("context=[" + s.substr(i-40, 80) + "]");
      var j = i + 1;
      var next = s.indexOf("\n", j);
      if (next < 0) next = s.length;
      Sys.println("nextLine=[" + s.substring(j, next) + "]");
    }
  }
}
