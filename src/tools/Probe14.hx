import hxunity.yaml.*;
class Probe14 {
  static function main() {
    var source = [
      "MonoBehaviour:",
      "  m_Name: ",
      "  _serializedGraph: '{\"type\":\"NodeCanvas\"},",
      "    more',",
      "  _objectReferences: []"
    ].join("\n") + "\n";
    var root = YamlParser.parse(source);
    var emitted = YamlWriter.write(root, {flowLineWidth: 100});
    Sys.println("--- emitted ---");
    for (line in emitted.split("\n")) Sys.println("|" + line + "|");
    var reparsed = YamlParser.parse(emitted);
    Sys.println("--- reparsed ---");
    for (line in YamlWriter.write(reparsed).split("\n")) Sys.println("|" + line + "|");
  }
}
