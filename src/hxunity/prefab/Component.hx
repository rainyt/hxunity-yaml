package hxunity.prefab;

import hxunity.yaml.ClassIds;
import hxunity.yaml.UnityYamlDocument;
import hxunity.yaml.YamlMap;
import hxunity.yaml.YamlNode;
import hxunity.yaml.YamlScalar;
import hxunity.yaml.YamlSeq;
import hxunity.yaml.YamlSeq;
import hxunity.unity.FileId;
import hxunity.unity.UnityReference;

/**
	A Unity component: anything attached to a [GameObjectObject].

	Common `Component` fields are exposed directly; everything else is reachable
	through the inherited field accessors.
**/
class Component extends UnityObject
{
	public function new(document:UnityYamlDocument, prefab:UnityPrefab)
	{
		super(document, prefab);
	}

	/**
		Creates the wrapper matching [document]'s class id.

		`MonoBehaviour` gets [MonoBehaviourObject], which resolves the script class
		name; every other class id gets a plain [Component], so an unknown
		component type is still fully usable.
	**/
	public static function create(document:UnityYamlDocument, prefab:UnityPrefab):Component
	{
		if (document.classId == ClassIds.MonoBehaviour) return new MonoBehaviourObject(document, prefab);
		return new Component(document, prefab);
	}

	/** The GameObject this component is attached to, or `null` when unattached. **/
	public function gameObject():GameObjectObject
	{
		var reference = getReference("m_GameObject");
		if (reference == null || reference.isExternal()) return null;
		return prefab.gameObjectById(reference.fileId);
	}

	/** Local file id of the owning GameObject, or `null` when unattached. **/
	public function gameObjectId()
	{
		return getReference("m_GameObject") == null ? null : getReference("m_GameObject").fileId;
	}

	/** `m_Enabled`, or `null` for components that do not serialise it. **/
	public function enabled():Null<Bool>
	{
		return getBool("m_Enabled");
	}

	/** Sets `m_Enabled`, adding the field when the component lacks it. **/
	public function setEnabled(value:Bool):Void
	{
		set("m_Enabled", new YamlScalar(value ? "1" : "0", hxunity.yaml.ScalarKind.Plain));
	}

	/** Detaches this component from its GameObject and removes its document. **/
	public function remove():Void
	{
		var owner = gameObject();
		if (owner != null)
		{
			var list = owner.componentReferences();
			if (list != null)
			{
				var index = list.length() - 1;
				while (index >= 0)
				{
					var item = list.get(index);
					if (Std.isOfType(item, YamlMap))
					{
						var map:YamlMap = cast item;
						var reference = UnityReference.fromNode(map.get("component"));
						if (reference != null && FileId.compare(reference.fileId, fileId()) == 0)
						{
							list.removeAt(index);
							break;
						}
					}
					index--;
				}
			}
		}
		prefab.removeObject(this);
	}
}
