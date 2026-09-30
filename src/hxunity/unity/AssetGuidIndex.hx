package hxunity.unity;

import haxe.Int64;
import haxe.ds.StringMap;

/**
	A project-wide index from asset GUID to asset.

	Unity identifies every asset by a 32 digit GUID stored in its `.meta` file, and
	serialised references point at each other by GUID rather than by path. Resolving
	`{fileID: 2100000, guid: 506c261d..., type: 2}` therefore needs a GUID to path
	map for the whole project, which is what this class holds.

	## Two levels

	* **Level 1 — the index itself.** One [AssetEntry] per asset, built from the
	  `.meta` files. It is cheap enough to cover every asset in a project, and it
	  answers "which file is this GUID?" and "what kind of asset is it?".
	* **Level 2 — asset contents.** Reading a `.mat` or `.prefab` to find out what
	  a particular `fileID` inside it is. That costs a full parse per file, so it
	  happens on demand and is remembered in a small map rather than being part of
	  the index.

	Most work only needs level 1.

	## Building it

	Three ways, in increasing cost:

	1. [locate] resolves a single GUID by walking the project tree for its `.meta`
	   file. No index, milliseconds, and it is what you want when a handful of
	   assets are involved.
	2. [scan] walks the tree once and indexes everything, which is what
	   [hxunity.unity.CachedGuidIndex] persists.
	3. [add] / [addEntry] fill the index from somewhere else, such as an export
	   produced by the Unity editor, which is both faster and more accurate than
	   any filesystem walk.
**/
class AssetGuidIndex
{
	/** Project root, or `null` when the index was not built from a project. **/
	public var projectRoot(default, null):String;

	/** Number of assets in the index. **/
	public function size():Int
	{
		return Lambda.count(entriesByGuid);
	}

	var entriesByGuid:StringMap<AssetEntry>;
	var guidByPath:StringMap<String>;
	var pathIndexReady:Bool;
	/** GUIDs looked up and not found, so a miss is not re-walked every time. **/
	var misses:StringMap<Bool>;
	/** Parsed asset bodies, keyed by GUID, for level 2 lookups. **/
	var documents:StringMap<hxunity.yaml.UnityDocumentSet>;

	public function new(?projectRoot:String)
	{
		this.projectRoot = resolveRoot(projectRoot);
		this.entriesByGuid = new StringMap();
		this.guidByPath = new StringMap();
		this.pathIndexReady = false;
		this.misses = new StringMap();
		this.documents = new StringMap();
	}

	/**
		Turns [projectRoot] into an absolute path.

		Asset paths are stored relative to the root, so the root has to be absolute
		for them to be derivable at all: a relative root would make every stored path
		depend on the reader's working directory, and the cache is shared between
		runs that may start anywhere.
	**/
	static function resolveRoot(projectRoot:String):String
	{
		if (projectRoot == null) return null;
		var normalised = ProjectFiles.normalise(projectRoot);
#if sys
		try
		{
			// `fullPath` rather than `absolutePath`: the latter resolves symlinks and
			// junctions, which on Windows can land outside what the caller may access.
			var absolute = sys.FileSystem.fullPath(normalised);
			if (absolute != null && absolute.length > 0) return ProjectFiles.normalise(absolute);
		}
		catch (e:Dynamic) {}
#end
		return normalised;
	}

	// ------------------------------------------------------------------ building

	/**
		Walks [root] and indexes every `.meta` file under it.

		Returns the number of assets indexed. Assets already present are replaced,
		so calling this twice is safe. Requires a `sys` target; on other targets it
		does nothing and returns 0.
	**/
	public function scan(root:String, ?options:ScanOptions):Int
	{
		this.projectRoot = root;
		return ProjectFiles.scanInto(this, root, options);
	}

	/** Adds [entry], replacing any existing asset with the same GUID. **/
	public function add(entry:AssetEntry):AssetEntry
	{
		if (entry == null || entry.guid == null) return entry;
		entry.guid = entry.guid.toLowerCase();
		entriesByGuid.set(entry.guid, entry);
		pathIndexReady = false;
		misses.remove(entry.guid);
		return entry;
	}

	/** Adds a prebuilt entry; kept for symmetry with [add]. **/
	public function addEntry(guid:String, path:String, kind:AssetKind, origin:Origin, mainId:Int64 = null,
			importer:String = null):AssetEntry
	{
		return add(new AssetEntry(guid, path, kind, origin, mainId, importer));
	}

	/**
		Forgets cached lookups.

		Call after the project changes on disk. Entries added by [add] or [scan] are
		kept; only the "not found" and parsed-document caches are dropped, because
		those are the ones that can go stale.
	**/
	public function invalidate():Void
	{
		misses = new StringMap();
		documents = new StringMap();
	}

	/**
		Re-reads one directory, replacing every asset it holds.

		[directory] is relative to the project root. Existing entries from that
		directory are dropped first, so an asset deleted from disk also leaves the
		index. Returns the GUIDs now indexed from that directory, which is what lets
		a caller record which assets belong to it.
	**/
	public function scanDirectory(directory:String):Array<String>
	{
		if (directory == null || projectRoot == null) return [];
		removeDirectory(directory);

		var found = [];
		ProjectFiles.scanDirectoryInto(this, projectRoot, directory, found);
		return found;
	}

	/** Drops the asset with [guid], or returns false when it was not indexed. **/
	public function remove(guid:String):Bool
	{
		if (guid == null) return false;
		var key = guid.toLowerCase();
		var entry = entriesByGuid.get(key);
		if (entry == null) return false;
		entriesByGuid.remove(key);
		if (entry.path != null) guidByPath.remove(normalisePath(entry.path));
		pathIndexReady = false;
		return true;
	}

	/**
		Drops every asset under [directory], including the directory's own.

		Used by an incremental refresh: when a directory's modification time says
		something was added or removed, nothing below it is trusted until it has been
		walked again. Assumes [directory] still exists — [removeDirectory] is the one
		to call for a directory that is gone, because it tolerates that.
	**/
	public function clearAssetsUnder(directory:String):Int
	{
		return removeDirectory(directory);
	}

	/** Drops every indexed asset whose path is inside [directory]. **/
	public function removeDirectory(directory:String):Int
	{
		if (directory == null) return 0;
		var prefix = normalisePath(directory);
		if (prefix.length > 0 && !StringTools.endsWith(prefix, "/")) prefix += "/";

		var doomed = [];
		for (entry in entriesByGuid)
		{
			if (entry.path == null) continue;
			var path = normalisePath(entry.path);
			// Either the path is the directory's own `.meta`, or it sits under it.
			if (path == normalisePath(directory) || StringTools.startsWith(path, prefix)) doomed.push(entry.guid);
		}
		for (guid in doomed)
		{
			var entry = entriesByGuid.get(guid);
			entriesByGuid.remove(guid);
			if (entry != null && entry.path != null) guidByPath.remove(normalisePath(entry.path));
		}
		if (doomed.length > 0) pathIndexReady = false;
		return doomed.length;
	}

	// ------------------------------------------------------------------ lookups

	/**
		The asset with [guid], or `null`.

		Looks in the index first. When the index does not have it and a
		[projectRoot] is known, walks the project to find the owning `.meta` file and
		remembers the result, so the first lookup pays for the walk and the rest are
		free. A GUID that is not found is remembered too, so a missing asset is not
		re-walked on every call.
	**/
	public function locate(guid:String):AssetEntry
	{
		if (guid == null) return null;
		var key = guid.toLowerCase();

		var cached = entriesByGuid.get(key);
		if (cached != null) return cached;
		if (misses.exists(key)) return null;
		if (projectRoot == null) return null;

		var found = ProjectFiles.findByGuid(projectRoot, key, BuiltinResources.isBuiltinGuid(key));
		if (found == null)
		{
			misses.set(key, true);
			return null;
		}
		return add(found);
	}

	/** Path of the asset with [guid] relative to the project root, or `null`. **/
	public function pathOf(guid:String):String
	{
		var entry = locate(guid);
		return entry == null ? null : entry.path;
	}

	/**
		Absolute path of the asset with [guid], or `null`.

		`null` for a built-in resource, and when no project root is known.
	**/
	public function absolutePathOf(guid:String):String
	{
		var entry = locate(guid);
		if (entry == null || entry.path == null || projectRoot == null) return null;
		return projectRoot + "/" + entry.path;
	}

	/** The asset stored at [path] (relative to the root), or `null`. **/
	public function guidOf(path:String):String
	{
		if (path == null) return null;
		ensurePathIndex();
		return guidByPath.get(normalisePath(path));
	}

	/** Every entry in the index. Order is unspecified. **/
	public function entries():Iterator<AssetEntry>
	{
		return entriesByGuid.iterator();
	}

	/** Number of assets of [kind] in the index. **/
	public function countOfKind(kind:AssetKind):Int
	{
		var total = 0;
		for (entry in entriesByGuid)
		{
			if (entry.kind == kind) total++;
		}
		return total;
	}

	// -------------------------------------------------------------- resolution

	/**
		Resolves a serialised reference to the asset it names.

		The returned [ResolvedReference] always describes what was found, including
		the cases where nothing was: a local reference, a built-in resource, and a
		GUID that is not in the project each report their own [Origin].
	**/
	public function resolve(reference:UnityReference):ResolvedReference
	{
		if (reference == null) return null;

		// No GUID: the reference stays inside the file it was written in.
		if (!reference.isExternal())
		{
			return new ResolvedReference(reference, null, Origin.Local, reference.fileId, false);
		}

		var guid = reference.guid.toLowerCase();

		// A built-in resource has no file anywhere, so it is answered from the
		// fixed table rather than by a lookup that could only ever fail.
		if (BuiltinResources.isBuiltinGuid(guid) && BuiltinResources.isObjectId(reference.fileId))
		{
			var builtin = new AssetEntry(guid, null, AssetKind.Unknown, Origin.Builtin, reference.fileId, null);
			return new ResolvedReference(reference, builtin, Origin.Builtin, reference.fileId, true);
		}

		var entry = locate(guid);
		if (entry == null)
		{
			return new ResolvedReference(reference, null, Origin.Missing, reference.fileId, false);
		}

		var isMain = entry.mainId != null && Int64.compare(entry.mainId, reference.fileId) == 0;
		return new ResolvedReference(reference, entry, entry.origin, reference.fileId, isMain);
	}

	/** Where [reference] points, without building the whole result. **/
	public function resolveOrigin(reference:UnityReference):Origin
	{
		var resolved = resolve(reference);
		return resolved == null ? Origin.Missing : resolved.origin;
	}

	/**
		True when [reference] names an object inside another project asset.

		This is the "can I read more here?" question: a local reference is already
		resolved by the file being read, and a built-in has no contents to read.
	**/
	public function isResolvableToFile(reference:UnityReference):Bool
	{
		var resolved = resolve(reference);
		return resolved != null && resolved.entry != null && resolved.entry.path != null;
	}

	// -------------------------------------------------------------- level 2

	/**
		Parses the asset a reference points into.

		This is the expensive level 2 operation: a whole file is read and parsed,
		then remembered for the next call. Returns `null` for a local or built-in
		reference, for a missing asset, and on a target without `sys`.
	**/
	public function loadAsset(reference:UnityReference):hxunity.prefab.UnityPrefab
	{
		var resolved = resolve(reference);
		if (resolved == null || resolved.entry == null || resolved.entry.path == null) return null;
		var path = projectRoot + "/" + resolved.entry.path;
		var documentSet = documentSetFor(resolved.entry.guid, path);
		if (documentSet == null) return null;
		return new hxunity.prefab.UnityPrefab(documentSet, path);
	}

	/** The parsed document set of the asset a reference points into, or `null`. **/
	public function documentSetOf(reference:UnityReference):hxunity.yaml.UnityDocumentSet
	{
		var resolved = resolve(reference);
		if (resolved == null || resolved.entry == null || resolved.entry.path == null) return null;
		return documentSetFor(resolved.entry.guid, projectRoot + "/" + resolved.entry.path);
	}

	/**
		The document a reference points at, resolved across files.

		A reference into a project asset names one document of that asset by
		`fileID`, so this reads the target asset and finds that document. A built-in
		reference always returns `null`, because there is no file to look in.
	**/
	public function resolveDocument(reference:UnityReference):hxunity.yaml.UnityYamlDocument
	{
		if (reference == null || reference.fileId == null) return null;
		var resolved = resolve(reference);
		if (resolved == null || resolved.entry == null) return null;

		// A reference to the asset's main object, or one that carries no useful
		// file id, is answered by the main object's own document.
		var documentSet = documentSetOf(reference);
		if (documentSet == null) return null;

		for (document in documentSet.documents)
		{
			if (Int64.compare(document.fileId, reference.fileId) == 0) return document;
		}
		return null;
	}

	function documentSetFor(guid:String, path:String):hxunity.yaml.UnityDocumentSet
	{
		var cached = documents.get(guid);
		if (cached != null) return cached;
		var text = ProjectFiles.readText(path);
		if (text == null) return null;
		var parsed = hxunity.yaml.UnityDocumentSet.parse(text);
		documents.set(guid, parsed);
		return parsed;
	}

	// ---------------------------------------------------------------- internals

	function ensurePathIndex():Void
	{
		if (pathIndexReady) return;
		guidByPath = new StringMap();
		for (entry in entriesByGuid)
		{
			if (entry.path != null) guidByPath.set(normalisePath(entry.path), entry.guid);
		}
		pathIndexReady = true;
	}

	/** Forward slashes, no leading `./`, for consistent path keys. **/
	public static function normalisePath(path:String):String
	{
		var text = StringTools.replace(path, "\\", "/");
		while (StringTools.startsWith(text, "./"))
		{
			text = text.substr(2);
		}
		return text;
	}

	public function toString():String
	{
		return 'AssetGuidIndex(${projectRoot == null ? "<no root>" : projectRoot}, ${size()} assets)';
	}
}
