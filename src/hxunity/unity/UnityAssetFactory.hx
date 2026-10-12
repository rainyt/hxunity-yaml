package hxunity.unity;

import haxe.Int64;
import hxunity.prefab.UnityPrefab;

/**
	Writes a whole asset — the file, its `.meta`, and the index entry — in one
	call.

	```haxe
	var index = cache.index;
	UnityAssetFactory.ensureFolder(projectRoot, "Assets/Psd/Hero", index);

	var texture = UnityAssetFactory.createTexture(projectRoot, "Assets/Psd/Hero/hand.png", pngBytes,
		TextureImportSettings.sprite(100), index);

	var material = UnityAssetFactory.createMaterial(projectRoot, "Assets/Psd/Hero/hand.mat", shaderGuid, "hand", index);
	var read = UnityMaterial.fromFile(projectRoot + "/" + material.path);
	read.setTexture("_MainTex", texture.guid);
	UnityAssetFactory.writeMaterial(projectRoot, material.path, read, index);

	var prefab = UnityPrefab.createEmpty();
	var root = prefab.createGameObject("hand");
	var renderer = root.addComponent("MeshRenderer");
	renderer.setSeq("m_Materials", [UnityReference.material(material.guid).toNode()]);
	UnityAssetFactory.createPrefab(projectRoot, "Assets/Psd/Hero/hand.prefab", prefab, index);

	// The exported asset is in the index straight away.
	Sys.println(index.locate(texture.guid).path);
	```

	Every call takes the project root first and the index last, so a batch export
	passes the same index down the line and each new asset is resolvable as soon
	as it is written — no rescan of the project between assets.

	## What is combined here

	The three steps Unity requires of any tool that adds an asset are easy to get
	individually right and easy to get *jointly* wrong:

	* the file itself;
	* its `.meta`, next to it, with the same name, carrying a GUID nothing else
	  in the project uses;
	* the index entry, so the rest of the session resolves the new GUID instead
	  of walking the project for it.

	The GUID is taken from [index] when one is given — [AssetGuidIndex.newGuid]
	checks the whole index in constant time — and from [AssetGuid.generate]
	otherwise. Passing an index also registers the entry, so
	`index.locate(entry.guid)` works immediately.

	## Reading back what was written

	[createMaterial] writes a `.mat` and returns its entry, but the material it
	wrote is not modified in place afterwards — a caller that wants to fill in
	textures reads the file back with [UnityMaterial.fromFile] and calls
	[writeMaterial]. That keeps one writer per asset: the file on disk is written
	by exactly one call, so a failed export never leaves a half filled material.
**/
class UnityAssetFactory
{
	/**
		Creates [folderPath] and every missing parent, each with its own `.meta`.

		Unity treats a directory without a `.meta` as a directory that is not part
		of the project: the assets inside it are not indexed and do not resolve.
		So a writer that creates `Assets/Psd/Hero/` has to create
		`Assets/Psd.meta` as well when `Assets/Psd/` is new, which is what this
		does. An existing folder is left alone, `.meta` included — its own GUID is
		already referenced by whatever points at it.
	**/
	public static function ensureFolder(projectRoot:String, folderPath:String, ?index:AssetGuidIndex):AssetEntry
	{
		var path = AssetGuidIndex.normalisePath(folderPath);
		if (StringTools.endsWith(path, "/")) path = path.substr(0, path.length - 1);
		var parts = path.split("/");
		var current = parts[0];
		var last:AssetEntry = null;
		for (i in 1...parts.length)
		{
			current = current + "/" + parts[i];
			last = ensureOneFolder(projectRoot, current, index);
		}
		// `Assets` on its own is the project's own root folder, never one this
		// creates, so a single segment path yields no entry.
		return parts.length > 1 ? last : null;
	}

	/** Creates one directory and its `.meta` when either is missing. **/
	static function ensureOneFolder(projectRoot:String, folderPath:String, index:AssetGuidIndex):AssetEntry
	{
		var absolute = absolutePathOf(projectRoot, folderPath);
		AssetWriter.ensureDirectory(absolute);
		var metaPath = AssetWriter.metaPathOf(absolute);
		if (!ProjectFiles.exists(metaPath))
		{
			var guid = newGuid(index);
			AssetWriter.saveText(metaPath, MetaWriter.forFolder(guid).emit());
			return register(projectRoot, index, folderPath, guid, AssetWriter.metaPathOf(folderPath));
		}
		if (index == null) return null;
		// A folder that is on disk but missing from the index is what a folder
		// created by another tool looks like; one read of it fixes that.
		var known = index.guidOf(folderPath);
		if (known == null)
		{
			index.scanDirectory(folderPath);
			known = index.guidOf(folderPath);
		}
		return known == null ? null : index.locate(known);
	}

	/**
		Writes [bytes] as a texture and creates its `.meta` with [settings].

		The returned entry's `guid` is what a material or a `SpriteRenderer`
		references, so the usual next call is
		`UnityMaterial.setTexture("_MainTex", entry.guid)`.
	**/
	public static function createTexture(projectRoot:String, assetPath:String, bytes:haxe.io.Bytes, ?settings:TextureImportSettings,
			?index:AssetGuidIndex, ?guid:String, ?templatePath:String):AssetEntry
	{
		require(projectRoot, assetPath);
		var id = resolveGuid(projectRoot, assetPath, guid, index);
		if (!AssetWriter.saveBytes(absolutePathOf(projectRoot, assetPath), bytes)) throw 'cannot write the texture "$assetPath"';
		return writeMeta(projectRoot, assetPath, MetaWriter.forTexture(id, settings, templatePath), index);
	}

	/** Creates only the `.meta` of a texture whose bytes are already on disk. **/
	public static function writeTextureMeta(projectRoot:String, assetPath:String, ?settings:TextureImportSettings, ?index:AssetGuidIndex,
			?guid:String, ?templatePath:String):AssetEntry
	{
		require(projectRoot, assetPath);
		var id = resolveGuid(projectRoot, assetPath, guid, index);
		return writeMeta(projectRoot, assetPath, MetaWriter.forTexture(id, settings, templatePath), index);
	}

	/**
		Creates a `.mat`.

		[shaderGuid] is the shader to reference, and [name] the material's own
		name; both default to something sensible (Unity's built-in Standard shader,
		and the file name without its extension).
	**/
	public static function createMaterial(projectRoot:String, assetPath:String, ?shaderGuid:String, ?name:String, ?index:AssetGuidIndex,
			?guid:String):AssetEntry
	{
		require(projectRoot, assetPath);
		var id = resolveGuid(projectRoot, assetPath, guid, index);
		var material = UnityMaterial.create(shaderGuid, name == null ? baseNameOf(assetPath) : name);
		return writeMaterial(projectRoot, assetPath, material, index, id);
	}

	/** Writes [material], which may have been built or read elsewhere. **/
	public static function writeMaterial(projectRoot:String, assetPath:String, material:UnityMaterial, ?index:AssetGuidIndex,
			?guid:String):AssetEntry
	{
		require(projectRoot, assetPath);
		var id = resolveGuid(projectRoot, assetPath, guid, index);
		if (!AssetWriter.saveText(absolutePathOf(projectRoot, assetPath), material.emit())) throw 'cannot write the material "$assetPath"';
		return writeMeta(projectRoot, assetPath, MetaWriter.forNativeAsset(id, Int64.ofInt(AssetReference.MATERIAL_ID)), index);
	}

	/** Writes [prefab] and creates its `.meta`. **/
	public static function createPrefab(projectRoot:String, assetPath:String, prefab:UnityPrefab, ?index:AssetGuidIndex,
			?guid:String):AssetEntry
	{
		require(projectRoot, assetPath);
		var id = resolveGuid(projectRoot, assetPath, guid, index);
		if (!AssetWriter.saveText(absolutePathOf(projectRoot, assetPath), prefab.emit())) throw 'cannot write the prefab "$assetPath"';
		return writeMeta(projectRoot, assetPath, MetaWriter.forPrefab(id), index);
	}

	// ------------------------------------------------------------------ plumbing

	/**
		Writes [meta] next to the asset at [assetPath] and registers the asset.

		The entry is built by parsing the `.meta` text that was just written, so
		the index sees exactly what is on disk — including a GUID the caller
		passed in — rather than what this method believes it wrote.
	**/
	public static function writeMeta(projectRoot:String, assetPath:String, meta:MetaDocument, ?index:AssetGuidIndex):AssetEntry
	{
		require(projectRoot, assetPath);
		var path = AssetGuidIndex.normalisePath(assetPath);
		if (!AssetWriter.saveText(absolutePathOf(projectRoot, AssetWriter.metaPathOf(path)), meta.emit()))
		{
			throw 'cannot write the .meta of "$assetPath"';
		}
		return register(projectRoot, index, path, meta.guid, AssetWriter.metaPathOf(path));
	}

	/** Builds the index entry for [assetPath] and adds it to the index. **/
	static function register(projectRoot:String, index:AssetGuidIndex, assetPath:String, guid:String, metaPath:String):AssetEntry
	{
		var parsed = MetaFile.parse(ProjectFiles.readText(absolutePathOf(projectRoot, metaPath)));
		var entry = AssetClassifier.build(parsed, assetPath, AssetClassifier.originOf(assetPath));
		if (entry.guid == null) entry.guid = guid;
		if (index != null) index.add(entry);
		return entry;
	}

	/** Absolute path of the project relative [assetPath]. **/
	public static function absolutePathOf(projectRoot:String, assetPath:String):String
	{
		if (assetPath == null) return null;
		var root = ProjectFiles.normalise(projectRoot);
		var path = AssetGuidIndex.normalisePath(assetPath);
		return StringTools.startsWith(path, root + "/") ? path : root + "/" + path;
	}

	/** A GUID nothing in [index] uses, or a fresh one when there is no index. **/
	public static function newGuid(?index:AssetGuidIndex):String
	{
		return index == null ? AssetGuid.generate() : index.newGuid();
	}

	/**
		The GUID to write for the asset at [assetPath].

		Three cases, in order:

		1. [guid] was passed, so that is the answer;
		2. a `.meta` already exists at the target, in which case its GUID is
		   **kept** — every reference to that asset is already written down, and a
		   re-export that minted a new GUID would silently break all of them. This
		   is what makes an interactive export work: exporting the same layer
		   twice updates the asset instead of orphaning it;
		3. nothing is there yet, so a fresh GUID is allocated.

		Case 2 is why the whole export flow can be re-run safely, and it is the
		behaviour Unity's own importer has: the `.meta` file, not the asset, is
		what carries the identity.
	**/
	public static function resolveGuid(projectRoot:String, assetPath:String, ?guid:String, ?index:AssetGuidIndex):String
	{
		if (guid != null) return guid;
		var existing = existingGuid(projectRoot, assetPath);
		return existing == null ? newGuid(index) : existing;
	}

	/** GUID of the `.meta` already on disk for [assetPath], or `null`. **/
	static function existingGuid(projectRoot:String, assetPath:String):String
	{
		var metaPath = AssetWriter.metaPathOf(assetPath);
		var text = ProjectFiles.readText(absolutePathOf(projectRoot, metaPath));
		if (text == null) return null;
		var meta = MetaFile.parse(text);
		return meta.guid;
	}

	/** Throws when a call is missing the two arguments every write needs. **/
	static function require(projectRoot:String, assetPath:String):Void
	{
		if (projectRoot == null || projectRoot.length == 0) throw "UnityAssetFactory needs a project root";
		if (assetPath == null || assetPath.length == 0) throw "UnityAssetFactory needs an asset path";
	}

	/** File name of [assetPath] without its extension, used as a default name. **/
	public static function baseNameOf(assetPath:String):String
	{
		if (assetPath == null) return "New Asset";
		var slash = assetPath.lastIndexOf("/");
		var name = slash < 0 ? assetPath : assetPath.substr(slash + 1);
		var dot = name.lastIndexOf(".");
		return dot <= 0 ? name : name.substring(0, dot);
	}
}
