package;

import hxunity.yaml.UnityDocumentSet;

/** Scratch probe: bisecting the wrapped-flow fixture. **/
class Probe8
{
	static function main()
	{
		check("unwrapped map", [
			"PrefabInstance:",
			"  m_Modification:",
			"    m_Modifications:",
			"    - target: {fileID: 1, guid: abc, type: 3}",
			"      propertyPath: m_Name",
			"      value: bananas",
			"    m_RemovedComponents: []",
			"  m_SourcePrefab: {fileID: 100100000, guid: abc, type: 3}"
		]);
		check("wrapped map", [
			"PrefabInstance:",
			"  m_Modification:",
			"    m_Modifications:",
			"    - target: {fileID: 1, guid: abc,",
			"        type: 3}",
			"      propertyPath: m_Name",
			"      value: bananas",
			"    m_RemovedComponents: []",
			"  m_SourcePrefab: {fileID: 100100000, guid: abc, type: 3}"
		]);
		check("wrapped map only", [
			"a:",
			"  b:",
			"  - target: {fileID: 1, guid: abc,",
			"      type: 3}",
			"    propertyPath: m_Name",
			"  c: 5"
		]);
	}

	static function check(label:String, parts:Array<String>):Void
	{
		var text = parts.join("\n") + "\n";
		Sys.println("=== " + label + " ===");
		var set = UnityDocumentSet.parse(text);
		Sys.println("  documents=" + set.count());
		Sys.println("  --- emitted ---");
		for (line in set.emit().split("\n")) Sys.println("  |" + line + "|");
	}
}
