package;

import hxunity.prefab.UnityPrefab;
import hxunity.yaml.ClassIds;

/** Scratch probe: counts documents by class id in a parsed prefab. **/
class Probe11
{
	static function main()
	{
		var prefab = UnityPrefab.parse(sys.io.File.getContent(Sys.args()[0]));
		var counts = new Map<Int, Int>();
		for (document in prefab.documents.documents)
		{
			var id = document.classId;
			counts.set(id, (counts.exists(id) ? counts.get(id) : 0) + 1);
		}
		for (id => count in counts)
		{
			Sys.println('classId=$id name=${ClassIds.name(id)} count=$count');
		}
		Sys.println("allComponentsOfType(Transform)=" + prefab.allComponentsOfType(ClassIds.Transform).length);
		Sys.println("allComponentsOfType(MeshRenderer)=" + prefab.allComponentsOfType(ClassIds.MeshRenderer).length);
		Sys.println("isComponent(Transform)=" + ClassIds.isComponent(ClassIds.Transform));
	}
}
