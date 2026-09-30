package;

import hxunity.prefab.UnityPrefab;

/** Scratch probe: inspects the hierarchy after a duplicate. **/
class Probe12
{
	static function main()
	{
		var text = [
			"%YAML 1.1",
			"%TAG !u! tag:unity3d.com,2011:",
			"--- !u!1 &100",
			"GameObject:",
			"  m_Component:",
			"  - component: {fileID: 101}",
			"  m_Name: Root",
			"--- !u!4 &101",
			"Transform:",
			"  m_GameObject: {fileID: 100}",
			"  m_Children:",
			"  - {fileID: 201}",
			"  m_Father: {fileID: 0}",
			"--- !u!1 &200",
			"GameObject:",
			"  m_Component:",
			"  - component: {fileID: 201}",
			"  - component: {fileID: 202}",
			"  m_Name: Child",
			"--- !u!4 &201",
			"Transform:",
			"  m_GameObject: {fileID: 200}",
			"  m_Children: []",
			"  m_Father: {fileID: 101}",
			"--- !u!23 &202",
			"MeshRenderer:",
			"  m_GameObject: {fileID: 200}",
			"  m_SortingOrder: 35"
		].join("\n") + "\n";

		var prefab = UnityPrefab.parse(text);
		var source = prefab.find("Child");
		Sys.println("before: documents=" + prefab.count());
		dump(prefab);
		var clone = prefab.duplicate(source);
		Sys.println("after: documents=" + prefab.count() + " clone=" + clone);
		dump(prefab);
		Sys.println("rootChildren=" + prefab.find("Root").children().length);
	}

	static function dump(prefab:UnityPrefab):Void
	{
		for (document in prefab.documents.documents)
		{
			Sys.println('  doc class=${document.className()} id=${haxe.Int64.toStr(document.fileId)} stripped=${document.stripped}');
		}
		for (object in prefab.allGameObjects())
		{
			var transform = object.transform();
			var children = transform == null ? [] : transform.childTransforms();
			var names = [];
			for (child in children)
			{
				var owner = child.gameObject();
				names.push(owner == null ? "?" : owner.name() + "@" + haxe.Int64.toStr(child.fileId()));
			}
			Sys.println('  object ${object.name()}@${haxe.Int64.toStr(object.fileId())} children=[${names.join(",")}]');
		}
	}
}
