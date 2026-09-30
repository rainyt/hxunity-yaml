package hxunity.unity;

/**
	Kind of asset a GUID names, derived from the `.meta` importer section and the
	file extension.

	The importer name alone is not enough: `NativeFormatImporter` covers `.mat`,
	`.asset`, `.controller` and `.anim` alike, because they are all serialised
	Unity objects. The extension breaks those ties, which is why [AssetGuidIndex]
	classifies on the pair rather than on the importer alone.
**/
enum abstract AssetKind(String)
{
	/** A serialised Unity object: `.mat`, `.asset`, `.controller`, `.anim`, ... **/
	var NativeAsset = "native";

	/** A texture or sprite: `.png`, `.jpg`, `.tga`, `.psd`, ... **/
	var Texture = "texture";

	/** An imported model: `.fbx`, `.obj`, `.blend`, ... **/
	var Model = "model";

	/** A prefab. **/
	var Prefab = "prefab";

	/** A C# script, or an assembly definition. **/
	var Script = "script";

	/** Plain text: `.txt`, `.json`, `.xml`, ... **/
	var Text = "text";

	/** An audio clip. **/
	var Audio = "audio";

	/** A video clip. **/
	var Video = "video";

	/** A shader. **/
	var Shader = "shader";

	/** A font. **/
	var Font = "font";

	/** A folder. Unity gives every folder a `.meta` with `folderAsset: yes`. **/
	var Folder = "folder";

	/** A native plugin. **/
	var Plugin = "plugin";

	/** Anything the importer table does not name. **/
	var Unknown = "unknown";

	/** The kind named by [text], or [Unknown] when it is not a known kind. **/
	public static function parse(text:String):AssetKind
	{
		if (text == null) return Unknown;
		return switch (text)
		{
			case "native": NativeAsset;
			case "texture": Texture;
			case "model": Model;
			case "prefab": Prefab;
			case "script": Script;
			case "text": Text;
			case "audio": Audio;
			case "video": Video;
			case "shader": Shader;
			case "font": Font;
			case "folder": Folder;
			case "plugin": Plugin;
			default: Unknown;
		}
	}

	/** True for a kind that holds serialised Unity objects rather than raw bytes. **/
	public function isUnitySerialised():Bool
	{
		return this == "native" || this == "prefab";
	}
}
