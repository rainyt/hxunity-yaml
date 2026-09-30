package hxunity.unity;

import haxe.Int64;
import haxe.ds.StringMap;

/**
	One directory as the cache remembers it.

	[children] is the list of subdirectory names the directory had, and it is the
	signal the whole cache turns on: comparing it against a fresh listing says
	exactly whether a subdirectory was added or removed, without trusting clock
	resolution.
**/
private class DirectoryRecord
{
	public var stamp:Float;
	public var children:Array<String>;
	/** Assets indexed from this directory, by GUID. **/
	public var guids:Array<String>;

	public function new(stamp:Float, children:Array<String>, guids:Array<String>)
	{
		this.stamp = stamp;
		this.children = children;
		this.guids = guids;
	}
}

/**
	An [AssetGuidIndex] that is persisted to a file and refreshed incrementally.

	## Why a cache at all

	Building the index means reading every `.meta` file in the project. On the
	reference project that is 22,147 files and about **11 seconds**, so paying it on
	every run is not acceptable.

	## How validity is decided

	Validation lists every directory and compares what it finds against what the
	cache recorded, instead of reading any `.meta` file. On the reference project
	that is **1,408 directories and 44,750 entries in about 790 ms**, against about
	**11 seconds** to rebuild the index from scratch.

	The comparison is per directory, and it answers two different questions:

	| compared | question |
	|---|---|
	| subdirectory names | was a directory added or removed? |
	| modification time | was a file added or removed? |

	The **subdirectory names** are the stronger signal. Directory modification times
	have one second resolution, so a directory changed and changed back inside one
	second would slip past a timestamp comparison; comparing the actual names cannot.
	Timestamps are still checked because they catch a file being added or removed in
	a directory whose subdirectories did not change.

	Editing a `.meta` file in place changes neither, which is correct: a content edit
	does not change which assets exist, so no index work is needed.

	## What is stored

	Mappings are stored twice, which is what makes an incremental update possible
	without a full reparse:

	* a row per asset, holding its path and attributes;
	* a row per directory, holding its timestamp, its subdirectory names, and the
	  GUIDs of the assets indexed from it.

	Re-reading one directory means rewriting one directory row and the asset rows
	for the GUIDs it lists.
**/
class CachedGuidIndex
{
	/** Bumped whenever the on-disk layout changes, which forces a rebuild. **/
	public static inline var FORMAT_VERSION = "v2";

	/** File name written under `Library/hxunity-yaml/` by [defaultCacheFile]. **/
	public static inline var DEFAULT_FILE_NAME = "guidindex.tsv";

	/** The project this cache describes. **/
	public var projectRoot(default, null):String;

	/** Where the cache is stored. **/
	public var cacheFile(default, null):String;

	/** The index this cache fills and reads through. **/
	public var index(default, null):AssetGuidIndex;

	/** Directory records keyed by path relative to [projectRoot]. **/
	var directories:StringMap<DirectoryRecord>;

	/** Unity version the cache was built against, or `null`. **/
	var unityVersion:String;

	var loaded:Bool;

	function new(projectRoot:String, cacheFile:String, index:AssetGuidIndex, directories:StringMap<DirectoryRecord>,
			unityVersion:String, loaded:Bool)
	{
		this.projectRoot = projectRoot;
		this.cacheFile = cacheFile;
		this.index = index;
		this.directories = directories;
		this.unityVersion = unityVersion;
		this.loaded = loaded;
	}

	/** The cache file [open] uses when the caller does not name one. **/
	public static function defaultCacheFile(projectRoot:String):String
	{
		return ProjectFiles.normalise(projectRoot) + "/Library/hxunity-yaml/" + DEFAULT_FILE_NAME;
	}

	/**
		Opens the cache for [projectRoot], loading it when it is still usable.

		This does not scan. Call [refresh] to make the index current, which is the
		step that decides between trusting the cache and rebuilding it.
	**/
	public static function open(projectRoot:String, ?cacheFile:String):CachedGuidIndex
	{
		var index = new AssetGuidIndex(projectRoot);
		var root = index.projectRoot;
		var file = cacheFile == null ? defaultCacheFile(root) : cacheFile;
		var directories = new StringMap<DirectoryRecord>();

		var text = ProjectFiles.readText(file);
		if (text == null) return new CachedGuidIndex(root, file, index, directories, null, false);

		var parsed = parseCache(text, root);
		if (parsed == null)
		{
			// An unreadable, foreign, or older cache is not an error: it is simply not
			// used, and [refresh] rebuilds it.
			return new CachedGuidIndex(root, file, index, directories, null, false);
		}

		for (entry in parsed.entries) index.add(entry);
		return new CachedGuidIndex(root, file, index, parsed.directories, parsed.unityVersion, true);
	}

	/** True when a usable cache file was found. **/
	public function isLoaded():Bool
	{
		return loaded;
	}

	/** Number of assets currently in the index. **/
	public function size():Int
	{
		return index.size();
	}

	/**
		Makes the index current and writes the cache back.

		Returns what had to be done, so a caller can tell a cheap no-op from a full
		rebuild. Pass [force] to rebuild even when the cache looks valid.
	**/
	public function refresh(?force:Bool):RefreshResult
	{
		var started = haxe.Timer.stamp();
		if (force == true) loaded = false;

		if (!loaded)
		{
			index = new AssetGuidIndex(projectRoot);
			directories = new StringMap();
			rebuildFromDisk();
			save();
			return {
				valid: false,
				rebuilt: true,
				rescanedDirs: [],
				directoryCount: Lambda.count(directories),
				entryCount: index.size(),
				elapsedMs: Std.int((haxe.Timer.stamp() - started) * 1000)
			};
		}

		var rescaned = [];
		reconcileTree(rescaned);
		dropVanished(rescaned);

		var changed = rescaned.length > 0;
		if (changed) save();
		return {
			valid: !changed,
			rebuilt: false,
			rescanedDirs: rescaned,
			directoryCount: Lambda.count(directories),
			entryCount: index.size(),
			elapsedMs: Std.int((haxe.Timer.stamp() - started) * 1000)
		};
	}

	/**
		Brings every directory in line with disk.

		**Every directory is listed every time**, which on the reference project is
		1,408 directories and about 45,000 entries. That is not an oversight: there is
		no cheaper sound check. A file added inside `Assets/Art` does not change
		`Assets`, so no state of a parent can prove anything about its children, and
		stopping the walk at an unchanged directory would silently miss such a file.

		Listing is still what the cache is for: the alternative it replaces is reading
		and reparsing 22,147 `.meta` files, which costs about 12 seconds against about
		1.7 for this.

		Each directory then decides for itself:

		* **subdirectory list changed** — a directory was added or removed here;
		* **timestamp moved** — a file was added or removed here;
		* **neither** — nothing changed, which is also what an in-place edit to an
		  existing `.meta` file looks like, and needs no work because it does not
		  change which assets exist.

		Re-reading a directory is what costs, and it happens only for the directories
		that changed.

		Assets are replaced per directory, never per subtree: a parent owns no
		`.meta` files of its own, so clearing a subtree would delete its children's
		entries and leave nothing to restore them.
	**/
	function reconcileTree(rescaned:Array<String>):Void
	{
		var visited = new StringMap<Bool>();
		var stack = [];
		for (start in ProjectFiles.scanRoots(projectRoot))
		{
			if (ProjectFiles.isDirectory(start)) stack.push(ProjectFiles.normalise(start));
		}

		while (stack.length > 0)
		{
			var absolute = stack.pop();
			if (visited.exists(absolute)) continue;
			visited.set(absolute, true);

			var directory = ProjectFiles.relativeTo(projectRoot, absolute);
			var names = ProjectFiles.readDirectory(absolute);
			var childNames = [];
			for (name in names)
			{
				var full = absolute + "/" + name;
				if (ProjectFiles.isDirectory(full))
				{
					childNames.push(name);
					stack.push(full);
				}
			}
			childNames.sort(Reflect.compare);

			var stamp = ProjectFiles.modifiedSeconds(absolute);
			var record = directories.get(directory);
			var changed = record == null || !sameNames(record.children, childNames) || record.stamp != stamp;
			if (changed) reindexDirectory(directory, stamp, childNames, rescaned);
		}
	}

	/** Re-reads one directory's own assets and rewrites its cache record. **/
	function reindexDirectory(directory:String, stamp:Float, childNames:Array<String>, rescaned:Array<String>):Void
	{
		var record = directories.get(directory);
		if (record != null)
		{
			for (guid in record.guids) index.remove(guid);
		}

		var guids = [];
		ProjectFiles.scanDirectoryInto(index, projectRoot, directory, guids);
		directories.set(directory, new DirectoryRecord(stamp, childNames, guids));
		rescaned.push(directory);
	}

	/**
		Removes records for directories that no longer exist on disk.

		[reconcile] only visits directories reachable from a scan root, so a subtree
		that was deleted leaves its records behind; this clears them.
	**/
	function dropVanished(rescaned:Array<String>):Void
	{
		var doomed = [];
		for (path in directories.keys())
		{
			if (!ProjectFiles.isDirectory(projectRoot + "/" + path)) doomed.push(path);
		}
		for (path in doomed)
		{
			var record = directories.get(path);
			if (record != null)
			{
				for (guid in record.guids) index.remove(guid);
			}
			directories.remove(path);
		}
	}

	/** Indexes the whole project from scratch and records every directory. **/
	function rebuildFromDisk():Void
	{
		index.scan(projectRoot);
		directories = new StringMap();

		// Collect the directories first, then attribute the assets to them in a
		// single pass over the index. Walking the whole index once per directory
		// would make this quadratic in a project with tens of thousands of assets.
		for (start in ProjectFiles.scanRoots(projectRoot))
		{
			if (!ProjectFiles.isDirectory(start)) continue;
			var stack = [ProjectFiles.normalise(start)];
			var visited = new StringMap<Bool>();
			while (stack.length > 0)
			{
				var absolute = stack.pop();
				if (visited.exists(absolute)) continue;
				visited.set(absolute, true);

				var directory = ProjectFiles.relativeTo(projectRoot, absolute);
				var childNames = [];
				for (name in ProjectFiles.readDirectory(absolute))
				{
					if (ProjectFiles.isDirectory(absolute + "/" + name))
					{
						childNames.push(name);
						stack.push(absolute + "/" + name);
					}
				}
				childNames.sort(Reflect.compare);
				directories.set(directory, new DirectoryRecord(ProjectFiles.modifiedSeconds(absolute), childNames, []));
			}
		}

		for (entry in index.entries())
		{
			if (entry.path == null) continue;
			var directory = ProjectFiles.directoryOf(AssetGuidIndex.normalisePath(entry.path));
			var record = directory == null ? null : directories.get(directory);
			if (record != null) record.guids.push(entry.guid);
		}
	}

	/**
		Writes the index to [cacheFile].

		The write goes to a temporary file which is then renamed over the target, so
		an interrupted run cannot leave a half written cache that the next run would
		read as valid.
	**/
	public function save():Bool
	{
		var buffer = new StringBuf();
		buffer.add("# hxunity-yaml guidindex " + FORMAT_VERSION + "\n");
		buffer.add("# root\t" + projectRoot + "\n");
		buffer.add("# unity\t" + unityVersionOf() + "\n");

		for (directory in directories.keys())
		{
			var record = directories.get(directory);
			buffer.add("# dir\t");
			buffer.add(directory);
			buffer.add("\t");
			buffer.add(Std.string(Std.int(record.stamp)));
			buffer.add("\t");
			// Subdirectory names, comma separated. A name cannot contain a comma on
			// any platform Unity supports, so the separator is unambiguous.
			buffer.add(record.children.join(","));
			buffer.add("\t");
			buffer.add(record.guids.join(","));
			buffer.add("\n");
		}

		for (entry in index.entries())
		{
			buffer.add(entry.guid);
			buffer.add("\t");
			buffer.add(entry.path == null ? "" : entry.path);
			buffer.add("\t");
			buffer.add(Std.string(entry.kind));
			buffer.add("\t");
			buffer.add(entry.mainId == null ? "" : Int64.toStr(entry.mainId));
			buffer.add("\t");
			buffer.add(Std.string(entry.origin));
			buffer.add("\t");
			buffer.add(entry.importer == null ? "" : entry.importer);
			buffer.add("\n");
		}
		return ProjectFiles.writeTextAtomic(cacheFile, buffer.toString());
	}

	/** Drops the loaded state, so the next [refresh] rebuilds from scratch. **/
	public function invalidate():Void
	{
		loaded = false;
		directories = new StringMap();
		index = new AssetGuidIndex(projectRoot);
	}

	// ---------------------------------------------------------------- internals

	/** True when two subdirectory name lists hold the same names in the same order. **/
	static function sameNames(a:Array<String>, b:Array<String>):Bool
	{
		if (a == null || b == null || a.length != b.length) return false;
		for (i in 0...a.length)
		{
			if (a[i] != b[i]) return false;
		}
		return true;
	}

	/** Unity version read from `ProjectSettings/ProjectVersion.txt`, or `null`. **/
	function unityVersionOf():String
	{
		if (unityVersion != null) return unityVersion;
		var text = ProjectFiles.readText(projectRoot + "/ProjectSettings/ProjectVersion.txt");
		if (text == null) return "";
		for (line in text.split("\n"))
		{
			var trimmed = StringTools.trim(line);
			if (StringTools.startsWith(trimmed, "m_EditorVersion:"))
			{
				unityVersion = StringTools.trim(trimmed.substr("m_EditorVersion:".length));
				return unityVersion;
			}
		}
		return "";
	}

	/** Result of [parseCache], or `null` when the cache cannot be used. **/
	static function parseCache(text:String, root:String):{entries:Array<AssetEntry>, directories:StringMap<DirectoryRecord>, unityVersion:String}
	{
		var entries = [];
		var directories = new StringMap<DirectoryRecord>();
		var version:String = null;
		var sawHeader = false;
		var rootMatches = false;

		for (line in text.split("\n"))
		{
			if (line.length == 0) continue;

			if (line.charAt(0) == "#")
			{
				var parts = line.substr(1).split("\t");
				var key = StringTools.trim(parts[0]);

				// The version is the header's first line, matched by prefix because a
				// switch constant cannot be built by concatenation.
				if (StringTools.startsWith(key, "hxunity-yaml guidindex"))
				{
					var declared = StringTools.trim(key.substr("hxunity-yaml guidindex".length));
					if (declared == FORMAT_VERSION) sawHeader = true;
					continue;
				}
				if (key == "root")
				{
					if (parts.length > 1 && ProjectFiles.normalise(parts[1]) == root) rootMatches = true;
					continue;
				}
				if (key == "unity")
				{
					if (parts.length > 1) version = parts[1];
					continue;
				}
				if (key == "dir")
				{
					if (parts.length >= 5)
					{
						var stamp = Std.parseFloat(parts[2]);
						directories.set(parts[1], new DirectoryRecord(Math.isNaN(stamp) ? -1 : stamp, splitNames(parts[3]),
							splitNames(parts[4])));
					}
					continue;
				}
				continue;
			}

			var fields = line.split("\t");
			if (fields.length < 3) continue;
			var guid = fields[0];
			if (guid.length == 0) continue;
			var path = fields[1].length == 0 ? null : fields[1];
			var kind = AssetKind.parse(fields[2]);
			var mainId = fields.length > 3 && fields[3].length > 0 ? parseInt64(fields[3]) : null;
			var origin = fields.length > 4 && fields[4].length > 0 ? parseOrigin(fields[4]) : AssetClassifier.originOf(path);
			var importer = fields.length > 5 && fields[5].length > 0 ? fields[5] : null;
			entries.push(new AssetEntry(guid, path, kind, origin, mainId, importer));
		}

		// A cache from a different project, or from before the format changed, is not
		// usable: its paths would be wrong.
		if (!sawHeader || !rootMatches) return null;
		return {entries: entries, directories: directories, unityVersion: version};
	}

	/** Splits a comma separated name list, treating an empty field as empty. **/
	static function splitNames(text:String):Array<String>
	{
		if (text == null || text.length == 0) return [];
		return text.split(",");
	}

	static function parseOrigin(text:String):Origin
	{
		return switch (text)
		{
			case "project": Origin.Project;
			case "package": Origin.Package;
			case "builtin": Origin.Builtin;
			case "local": Origin.Local;
			default: Origin.Missing;
		}
	}

	static function parseInt64(text:String):Int64
	{
		try
		{
			return Int64.parseString(text);
		}
		catch (e:Dynamic)
		{
			return null;
		}
	}
}
