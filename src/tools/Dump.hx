package;

import hxunity.yaml.YamlParser;
import hxunity.yaml.YamlNode;
import hxunity.yaml.YamlMap;
import hxunity.yaml.YamlSeq;
import hxunity.yaml.YamlScalar;
import hxunity.yaml.UnityDocumentSet;

/** Dumps the parsed structure of a Unity YAML file. **/
class Dump
{
	static function main()
	{
		var args = Sys.args();
		var path = args[0];
		var text = sys.io.File.getContent(path);
		var set = UnityDocumentSet.parse(text, {trackPositions: true});
		Sys.println("documents=" + set.count() + " preamble=" + set.preamble);
		for (document in set.documents)
		{
			Sys.println("--- " + document.toString());
			dump(document.body, 1);
		}
	}

	static function dump(node:YamlNode, depth:Int):Void
	{
		var pad = hxunity.yaml.Strings.spaces(depth * 2);
		if (Std.isOfType(node, YamlMap))
		{
			var map:YamlMap = cast node;
			for (entry in map.entries)
			{
				if (entry.value.isCollection())
				{
					Sys.println(pad + entry.key + ": " + entry.value.typeName() + " @" + entry.value.line);
					dump(entry.value, depth + 1);
				}
				else
				{
					var s:YamlScalar = cast entry.value;
					Sys.println(pad + entry.key + ": [" + s.kind + "] '" + s.raw + "' @" + s.line);
				}
			}
			return;
		}
		var seq:YamlSeq = cast node;
		for (item in seq.items)
		{
			if (item.isCollection())
			{
				Sys.println(pad + "- " + item.typeName() + " @" + item.line);
				dump(item, depth + 1);
			}
			else
			{
				var s:YamlScalar = cast item;
				Sys.println(pad + "- [" + s.kind + "] '" + s.raw + "' @" + s.line);
			}
		}
	}
}
