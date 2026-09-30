package;

import hxunity.yaml.UnityDocumentSet;

/** Scratch probe: prints each parsed document of a file or fixture. **/
class Probe6
{
	static function main()
	{
		var text = [
			"%YAML 1.1",
			"%TAG !u! tag:unity3d.com,2011:",
			"PrefabInstance:",
			"  m_SourcePrefab: {fileID: 100100000, guid: 75e48dfe44cab60438c20657f7f6f739, type: 3}",
			"--- !u!4 &8187102978003566204 stripped",
			"Transform:",
			"  m_PrefabInstance: {fileID: 5693881486261822889}"
		].join("\n") + "\n";
		var set = UnityDocumentSet.parse(text);
		Sys.println("count=" + set.count() + " preamble=" + set.preamble.join("|"));
		for (document in set.documents)
		{
			Sys.println('  classId=${document.classId} id=${haxe.Int64.toStr(document.fileId)} header=${document.hasHeader} name=${document.className()} line=${document.documentLine} bodyKeys='
				+ bodyKeys(document));
		}
	}

	static function bodyKeys(document:hxunity.yaml.UnityYamlDocument):String
	{
		if (!Std.isOfType(document.body, hxunity.yaml.YamlMap)) return "<not a map>";
		var map:hxunity.yaml.YamlMap = cast document.body;
		var keys = [];
		for (entry in map.entries) keys.push(entry.key);
		return keys.join(",");
	}
}
