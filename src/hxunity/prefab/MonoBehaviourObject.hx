package hxunity.prefab;

import hxunity.yaml.UnityYamlDocument;
import hxunity.yaml.YamlScalar;
import hxunity.yaml.ScalarKind;
import hxunity.unity.UnityReference;

/**
	A `MonoBehaviour` component.

	The interesting field is `m_Script`, which points at a `MonoScript` asset
	whose `m_ClassName` / `m_Namespace` say which C# class the component is. The
	script lives in the project, not in this file, so resolving it needs the
	project's `.meta` files; [assign] takes that map.

	`m_EditorClassIdentifier` is Unity's fallback and is often empty in a prefab
	that has never been opened in the editor.
**/
class MonoBehaviourObject extends Component
{
	public function new(document:UnityYamlDocument, prefab:UnityPrefab)
	{
		super(document, prefab);
	}

	/** `m_Script`, or `null` when the field is missing. **/
	public function scriptReference():UnityReference
	{
		return getReference("m_Script");
	}

	/** GUID of the script asset, or `null` when it is not set. **/
	public function scriptGuid():String
	{
		var reference = scriptReference();
		return reference == null ? null : reference.guid;
	}

	/** `m_EditorClassIdentifier`, or `null`. **/
	public function editorClassIdentifier():String
	{
		return getString("m_EditorClassIdentifier");
	}

	/**
		Class name of the script, when the prefab itself records it.

		Returns `null` for the common case where the prefab only stores a GUID;
		use [resolveClassName] with a GUID index to look it up in the project.
	**/
	public function ownClassName():String
	{
		var identifier = getString("m_ClassName");
		if (identifier != null) return identifier;
		var type = getString("m_Type");
		return type;
	}

	/**
		Resolves the C# class name through [scriptGuids].

		[scriptGuids] maps a script GUID to its class name, which a caller builds
		from the project's `MonoScript` assets (see
		[hxunity.unity.AssetGuidIndex]).
	**/
	public function resolveClassName(scriptGuids:Map<String, String>):String
	{
		var own = ownClassName();
		if (own != null) return own;
		var guid = scriptGuid();
		if (guid == null || scriptGuids == null) return null;
		return scriptGuids.get(guid);
	}

	/**
		Points `m_Script` at another script asset.

		Both `m_EditorClassIdentifier` and `m_ClassName` are cleared, because
		leaving them behind would make Unity show the old script name until the
		component is reimported.
	**/
	public function assignScript(guid:String, fileId:haxe.Int64):Void
	{
		set("m_Script", UnityReference.asset(guid, fileId, UnityReference.TYPE_PROJECT).toNode());
		if (hasField("m_EditorClassIdentifier")) set("m_EditorClassIdentifier", new YamlScalar("", ScalarKind.Plain));
		removeField("m_ClassName");
		removeField("m_Namespace");
	}
}
