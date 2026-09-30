package;

import hxunity.yaml.YamlParser;
import hxunity.yaml.YamlLexer;
import hxunity.yaml.YamlMap;
import hxunity.yaml.YamlSeq;
import hxunity.yaml.YamlNode;

/** Scratch probe: prints the parsed tree of a fixture. **/
class Probe9
{
	static function main()
	{
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
		var root = YamlParser.parse(text);
		dump(root, 0);
	}

	static function dump(node:YamlNode, depth:Int):Void
	{
		var pad = hxunity.yaml.Strings.spaces(depth * 2);
		if (Std.isOfType(node, YamlMap))
		{
			var map:YamlMap = cast node;
			for (entry in map.entries)
			{
				Sys.println(pad + entry.key + ":");
				dump(entry.value, depth + 1);
			}
			return;
		}
		if (Std.isOfType(node, YamlSeq))
		{
			var seq:YamlSeq = cast node;
			for (item in seq.items)
			{
				Sys.println(pad + "-");
				dump(item, depth + 1);
			}
			return;
		}
		Sys.println(pad + "'" + node.toString() + "'");
	}
}
