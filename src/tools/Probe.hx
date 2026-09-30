import hxunity.yaml.UnityDocumentSet;
class Probe {
  static function main() {
    var text = sys.io.File.getContent(Sys.args()[0]);
    var set = UnityDocumentSet.parse(text);
    var out = set.emit();
    var lines = out.split("\n");
    for (i in 0...12) Sys.println(i + ": |" + lines[i] + "|");
    Sys.println("doc0 body type=" + Type.getClassName(Type.getClass(set.at(0).body)));
    var m:hxunity.yaml.YamlMap = cast set.at(0).body;
    for (e in m.entries) Sys.println("  key=" + e.key + " value=" + Type.getClassName(Type.getClass(e.value)));
  }
}
