package;

import hxunity.yaml.UnityDocumentSet;

/** Scratch probe: the wrapped quoted scalar fixture from the test suite. **/
class Probe15
{
	static function main()
	{
		var source = [
			"MonoBehaviour:",
			"  m_Name: ",
			"  _serializedGraph: '{\"type\":\"NodeCanvas.DialogueTrees.DialogueTree\",\"nodes\":[{\"gridPosition\":{\"x\":103.0,\"y\":130.0},",
			"    \"positionDir\":4,\"$type\":\"Action_CreateNPC\"}],\"canvasGroups\":null,\"localBlackboard\":{\"_variables\":{\"Separator|",
			"    (Double Click To Rename)\":{\"_value\":{},\"_name\":\"Separator (Double Click To Rename)\"}}}}'",
			"  _objectReferences: []"
		].join("\n") + "\n";
		var set = UnityDocumentSet.parse(source);
		Sys.println("documents=" + set.count());
		var body = set.at(0).body.asMap();
		for (entry in body.entries)
		{
			Sys.println("body key=" + entry.key + " class=" + Type.getClassName(Type.getClass(entry.value)));
		}
		var behaviour = body.getMap("MonoBehaviour");
		Sys.println("behaviour=" + (behaviour == null ? "null" : "map"));
		if (behaviour != null)
		{
			for (entry in behaviour.entries)
			{
				Sys.println("  field=" + entry.key + " class=" + Type.getClassName(Type.getClass(entry.value)) + " isScalar="
					+ Std.isOfType(entry.value, hxunity.yaml.YamlScalar));
			}
			var graph = behaviour.get("_serializedGraph");
			Sys.println("  graph isScalar=" + Std.isOfType(graph, hxunity.yaml.YamlScalar) + " value="
				+ (graph == null ? "null" : graph.toString()));
		}
		Sys.println("--- emitted ---");
		for (line in set.emit().split("\n")) Sys.println("|" + line + "|");
	}
}
