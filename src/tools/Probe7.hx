package;

import hxunity.yaml.UnityDocumentSet;

/** Scratch probe: prints each document of the wrapped-flow fixture. **/
class Probe7
{
	static function main()
	{
		var text = [
			"PrefabInstance:",
			"  serializedVersion: 2",
			"  m_Modification:",
			"    m_Modifications:",
			"    - target: {fileID: 4511153011648551893, guid: 75e48dfe44cab60438c20657f7f6f739,",
			"        type: 3}",
			"      propertyPath: m_Name",
			"      value: banquet_0205_14",
			"      objectReference: {fileID: 0}",
			"    m_RemovedComponents: []",
			"  m_SourcePrefab: {fileID: 100100000, guid: 75e48dfe44cab60438c20657f7f6f739, type: 3}",
			"--- !u!4 &8187102978003566204 stripped",
			"Transform:",
			"  m_CorrespondingSourceObject: {fileID: 4511153011648551893, guid: 75e48dfe44cab60438c20657f7f6f739,",
			"    type: 3}",
			"  m_PrefabInstance: {fileID: 5693881486261822889}",
			"  m_PrefabAsset: {fileID: 0}"
		].join("\n") + "\n";
		var set = UnityDocumentSet.parse(text);
		Sys.println("count=" + set.count());
		for (document in set.documents)
		{
			Sys.println('  classId=${document.classId} header=${document.hasHeader} name=${document.className()} line=${document.documentLine}');
		}
		var dump = new StringBuf();
		for (line in set.emit().split("\n")) dump.add("|" + line + "|\n");
		Sys.println(dump.toString());
	}
}
