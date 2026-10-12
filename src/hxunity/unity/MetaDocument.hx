package hxunity.unity;

import haxe.Int64;
import hxunity.yaml.ScalarKind;
import hxunity.yaml.Scalars;
import hxunity.yaml.UnityDocumentSet;
import hxunity.yaml.YamlMap;
import hxunity.yaml.YamlNode;
import hxunity.yaml.YamlScalar;

/**
	A writable Unity `.meta` file.

	[MetaFile] reads the four fields an index needs and stops; this is the other
	direction: the whole file, as an editable model, with the two properties that
	make it safe to write back.

	## Round tripping

	[MetaDocument.parse] keeps the parsed mapping and [emit] writes that mapping
	out again, so everything a `.meta` carries is preserved: the field order the
	importer wrote, the fields this library has never heard of, and the
	`serializedVersion` each importer section declares. Rewriting a `.meta` to
	change one value therefore produces a one-line change rather than a file Unity
	would rewrite wholesale the next time it imports the asset.

	## The file's shape

	```yaml
	fileFormatVersion: 2
	guid: 9e613c018e232044db897e24a5e4fd3f
	folderAsset: yes          # folders only
	DefaultImporter:
	  externalObjects: {}
	  userData: 
	  assetBundleName: 
	  assetBundleVariant: 
	```

	Two details are easy to get wrong and are handled here rather than by the
	caller:

	* the **GUID is a top level key** and comes before the importer section;
	* **empty values keep a trailing space** (`userData: `), which is what Unity
	  2022.3 writes — 2,802 of 2,804 sampled `.meta` files in a real project have
	  that space, and the writer keeps it.
**/
class MetaDocument
{
	/** `fileFormatVersion`, always 2 for the `.meta` files this writes. **/
	public var fileFormatVersion(default, null):Int = 2;

	/** Importer section name, e.g. `TextureImporter`. **/
	public var importer(default, null):String;

	/** The asset GUID, the top level `guid:` key. **/
	public var guid(get, set):String;

	/** True when this `.meta` describes a folder (`folderAsset: yes`). **/
	public var isFolder(get, set):Bool;

	/**
		`mainObjectFileID` of a `NativeFormatImporter`, or `null`.

		Only a native asset has one: it names the object inside the file that
		references should point at (2100000 for a `.mat`, 11400000 for a
		`.asset`), which is why a reference can carry a GUID without a per asset
		file id in hand.
	**/
	public var mainObjectFileId(get, set):Int64;

	/** The whole `.meta` mapping, in file order. **/
	var root:YamlMap;

	public function new(root:YamlMap, importer:String)
	{
		this.root = root == null ? new YamlMap() : root;
		this.importer = importer;
	}

	/**
		An empty `.meta` for [guid] with an importer section named [importer].

		The section is created with `externalObjects: {}` and the three empty
		fields every importer shares, which is where the per importer factories in
		[MetaWriter] start. [folder] adds `folderAsset: yes`, which Unity writes
		between the GUID and the importer section.
	**/
	public static function create(guid:String, importer:String, folder:Bool = false):MetaDocument
	{
		var root = new YamlMap();
		root.set("fileFormatVersion", plain("2"));
		root.set("guid", Scalars.ofString(requireGuid(guid)));
		if (folder) root.set("folderAsset", plain("yes"));
		root.set(importer, defaultSection());
		return new MetaDocument(root, importer);
	}

	/**
		Reads a `.meta` file's text into an editable document.

		Nothing throws: a file this does not understand yields a document whose
		fields are empty, because one odd `.meta` must not abort a whole export.
	**/
	public static function parse(text:String):MetaDocument
	{
		var set = text == null ? null : UnityDocumentSet.parse(text);
		var document = set == null ? null : set.firstOfClass(0);
		if (document == null && set != null && set.count() > 0) document = set.at(0);
		var root:YamlMap = null;
		if (document != null && Std.isOfType(document.body, YamlMap))
		{
			root = cast document.body;
		}
		var importer = importerOf(root);
		var meta = new MetaDocument(root, importer == null ? "DefaultImporter" : importer);
		var version = meta.get("fileFormatVersion");
		if (version != null)
		{
			var parsed = Scalars.tryInt(version.toString());
			if (parsed != null) meta.fileFormatVersion = parsed;
		}
		return meta;
	}

	/** Reads a `.meta` file from disk, or `null` when it cannot be read. **/
	public static function fromFile(path:String):MetaDocument
	{
		var text = ProjectFiles.readText(path);
		return text == null ? null : parse(text);
	}

	/** The importer section name in [root], the first key ending in `Importer`. **/
	static function importerOf(root:YamlMap):String
	{
		if (root == null) return null;
		for (entry in root.entries)
		{
			if (entry.key.length > "Importer".length && StringTools.endsWith(entry.key, "Importer"))
			{
				return entry.key;
			}
		}
		return null;
	}

	/** The four fields every importer section starts with, in Unity's order. **/
	static function defaultSection():YamlMap
	{
		var section = new YamlMap();
		section.set("externalObjects", new YamlMap(null, true));
		section.set("userData", plain(""));
		section.set("assetBundleName", plain(""));
		section.set("assetBundleVariant", plain(""));
		return section;
	}

	/** The asset GUID, from the top level `guid:` key. **/
	function get_guid():String
	{
		var node = root.get("guid");
		return node == null ? null : AssetGuid.normalise(node.toString());
	}

	/**
		Sets the GUID, keeping its position at the top of the file.

		A `null` or empty GUID is refused rather than written: an asset whose
		`.meta` has no GUID is one no reference can ever reach, and the failure
		shows up much later as a missing texture.
	**/
	function set_guid(value:String):String
	{
		var text = requireGuid(value);
		root.set("guid", Scalars.ofString(text));
		return text;
	}

	/**
		The canonical GUID text, or throws when there is none.

		A `.meta` without a GUID describes an asset no reference can ever reach,
		and the failure surfaces much later as a missing texture, so it is refused
		here rather than written.
	**/
	public static function requireGuid(guid:String):String
	{
		var text = AssetGuid.normalise(guid);
		if (text == null || text.length == 0) throw "a .meta file needs a GUID; pass one from AssetGuid.generate()";
		return text;
	}

	function get_isFolder():Bool
	{
		var node = root.get("folderAsset");
		return node != null && Scalars.tryBool(node.toString()) == true;
	}

	function set_isFolder(value:Bool):Bool
	{
		if (value)
		{
			// `yes`, not `true`: Unity writes the YAML 1.1 spelling, and the
			// library's reader accepts both.
			root.set("folderAsset", new YamlScalar("yes", ScalarKind.Plain));
		}
		else
		{
			root.remove("folderAsset");
		}
		return value;
	}

	/** The whole mapping, for a caller that needs a field this class does not model. **/
	public function fields():YamlMap
	{
		return root;
	}

	/** The importer section mapping. **/
	public function section():YamlMap
	{
		var existing = root.getMap(importer);
		if (existing != null) return existing;
		var created = defaultSection();
		root.set(importer, created);
		return created;
	}

	function get_mainObjectFileId():Int64
	{
		var node = section().get("mainObjectFileID");
		return node == null ? null : Scalars.tryInt64(node.toString());
	}

	function set_mainObjectFileId(value:Int64):Int64
	{
		var section = section();
		var text = value == null ? "0" : FileId.toStr(value);
		var existing = section.get("mainObjectFileID");
		if (existing != null && Std.isOfType(existing, YamlScalar))
		{
			(cast existing : YamlScalar).setRaw(text);
			return value;
		}
		// A missing field is inserted right after `externalObjects`, where Unity
		// writes it, by rebuilding the entries in one pass — a caller that hands
		// this a template from an importer which never wrote the field still gets
		// Unity's order rather than the field appended at the end.
		var rebuilt = new YamlMap();
		for (entry in section.entries)
		{
			if (entry.key == "mainObjectFileID") continue;
			rebuilt.add(entry.key, entry.value);
			if (entry.key == "externalObjects") rebuilt.add("mainObjectFileID", plain(text));
		}
		if (!rebuilt.has("mainObjectFileID")) rebuilt.add("mainObjectFileID", plain(text));
		replaceEntries(section, rebuilt);
		return value;
	}

	/** Moves [source]'s entries into [target], keeping their order. **/
	static function replaceEntries(target:YamlMap, source:YamlMap):Void
	{
		while (target.entries.length > 0)
		{
			target.remove(target.entries[0].key);
		}
		for (entry in source.entries)
		{
			target.add(entry.key, entry.value);
		}
	}

	// ------------------------------------------------------------ field access

	/** Field of the importer section, or `null`. **/
	public function get(key:String):YamlNode
	{
		return section().get(key);
	}

	/** Field text of the importer section, or `null`. **/
	public function getString(key:String):String
	{
		return section().getString(key);
	}

	/** Field of the importer section as an int, or `null`. **/
	public function getInt(key:String):Null<Int>
	{
		return section().getInt(key);
	}

	/** Field of the importer section as a float, or `null`. **/
	public function getFloat(key:String):Null<Float>
	{
		return section().getFloat(key);
	}

	/** Field of the importer section as a bool, or `null`. **/
	public function getBool(key:String):Null<Bool>
	{
		return section().getBool(key);
	}

	/** Stores [value] in the importer section, replacing a field in place. **/
	public function set(key:String, value:YamlNode):YamlNode
	{
		return section().set(key, value);
	}

	/** Stores plain text, quoted when a bare value would not read back the same. **/
	public function setString(key:String, value:String):Void
	{
		section().set(key, Scalars.ofString(value));
	}

	/** Stores an integer field. **/
	public function setInt(key:String, value:Int):Void
	{
		section().set(key, plain(Std.string(value)));
	}

	/** Stores a float field, formatted the way Unity writes floats. **/
	public function setFloat(key:String, value:Float):Void
	{
		section().set(key, plain(hxunity.types.Numbers.format(value)));
	}

	/** Stores a boolean field as Unity's `1` / `0`. **/
	public function setBool(key:String, value:Bool):Void
	{
		section().set(key, plain(value ? "1" : "0"));
	}

	/** Removes a field, returning it when it was there. **/
	public function remove(key:String):YamlNode
	{
		return section().remove(key);
	}

	/** True when the importer section has [key]. **/
	public function has(key:String):Bool
	{
		return section().has(key);
	}

	/**
		Field of the importer section at a dotted [path], e.g. `mipmaps.sRGBTexture`.

		Importer sections are two levels deep in places (`mipmaps`, `bumpmap`,
		`textureSettings`), and a path is easier to pass around than a chain of
		`getMap` calls.
	**/
	public function getPath(path:String):YamlNode
	{
		var map = section();
		var parts = path.split(".");
		for (i in 0...parts.length)
		{
			if (map == null) return null;
			if (i == parts.length - 1) return map.get(parts[i]);
			map = map.getMap(parts[i]);
		}
		return null;
	}

	/** Stores [value] at a dotted [path], creating the intermediate mappings. **/
	public function setPath(path:String, value:YamlNode):YamlNode
	{
		var map = section();
		var parts = path.split(".");
		for (i in 0...parts.length - 1)
		{
			var child = map.getMap(parts[i]);
			if (child == null)
			{
				child = new YamlMap();
				map.set(parts[i], child);
			}
			map = child;
		}
		return map.set(parts[parts.length - 1], value);
	}

	/** Field text at a dotted [path], or `null`. **/
	public function getStringPath(path:String):String
	{
		var node = getPath(path);
		return (node == null || node.isCollection()) ? null : node.toString();
	}

	/** Integer field at a dotted [path], or `null`. **/
	public function getIntPath(path:String):Null<Int>
	{
		var text = getStringPath(path);
		return text == null ? null : Scalars.tryInt(text);
	}

	/** Stores plain text at a dotted [path]. **/
	public function setStringPath(path:String, value:String):Void
	{
		setPath(path, Scalars.ofString(value));
	}

	/** Stores an integer at a dotted [path]. **/
	public function setIntPath(path:String, value:Int):Void
	{
		setPath(path, plain(Std.string(value)));
	}

	// ------------------------------------------------------------------ output

	/** The whole `.meta` file as text: LF endings, one trailing newline, no BOM. **/
	public function emit():String
	{
		var set = new UnityDocumentSet([], [headerless()], "\n", true);
		return set.emit();
	}

	/**
		The document wrapper for the mapping.

		A `.meta` file has no `--- !u!` header — it is a bare mapping — so the
		document is built with [UnityYamlDocument.hasHeader] false, which is what
		keeps [emit] from inventing one.
	**/
	function headerless():hxunity.yaml.UnityYamlDocument
	{
		return new hxunity.yaml.UnityYamlDocument(0, FileId.zeroId(), false, root, 0, false, false);
	}

	/** Writes the file to [path], creating the parent directory when needed. **/
	public function save(path:String):Bool
	{
		return AssetWriter.saveText(path, emit());
	}

	/** Path of the asset this `.meta` belongs to, derived from [metaPath]. **/
	public static function assetPathOf(metaPath:String):String
	{
		return AssetWriter.assetPathOf(metaPath);
	}

	/** Path of the `.meta` file of the asset at [assetPath]. **/
	public static function metaPathOf(assetPath:String):String
	{
		return AssetWriter.metaPathOf(assetPath);
	}

	static function plain(text:String):YamlScalar
	{
		return new YamlScalar(text, ScalarKind.Plain);
	}

	public function toString():String
	{
		return 'MetaDocument(guid=$guid importer=$importer folder=$isFolder)';
	}
}
