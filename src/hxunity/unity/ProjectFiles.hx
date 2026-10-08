package hxunity.unity;

import haxe.Int64;
import haxe.ds.StringMap;

/**
	Filesystem access for [AssetGuidIndex], isolated so the rest of the library
	still compiles on targets without `sys`.

	Everything here returns `null` or 0 when `sys` is unavailable rather than
	failing to compile, so an index can always be built by hand with
	[AssetGuidIndex.add] on any target.

	## Walking rules

	* `Library/`, `Temp/`, `obj/`, `Build/`, `Logs/` and `.git` are skipped: they
	  hold copies and generated output, not authored assets, and `Library/` alone
	  is far larger than `Assets/`.
	* A directory is never entered twice, which is what keeps a symlink or a
	  Windows junction pointing back up the tree from looping forever.
**/
class ProjectFiles
{
#if (sys || hxnodejs)
	/**
		Directory names never descended into, lowercased.

		Only names that cannot hold authored content are listed. `Build`, `obj` and
		`Temp` were deliberately removed from an earlier version of this list: a
		project may legitimately keep content in `Assets/Art/Build/` or
		`Assets/.../obj/`, and skipping by name hid half of the reference project.
		Unity's own generated trees live at the project root, where the walk never
		goes because it starts at `Assets/` and `Packages/`.
	**/
	static var DEFAULT_SKIP = ["library", "logs", ".git", ".svn", "node_modules"];
#end

	/**
		Finds the asset with [guid] by walking [root], or returns `null`.

		This is the lazy path: a single GUID is resolved without indexing anything,
		which costs one tree walk rather than a full index build.

		[isBuiltin] is passed in so a built-in GUID is not looked for on disk, where
		it could not exist.
	**/
	public static function findByGuid(root:String, guid:String, isBuiltin:Bool):AssetEntry
	{
		if (isBuiltin) return null;
#if (sys || hxnodejs)
		if (root == null || guid == null) return null;
		var skip = buildSkip(null);
		var visited = new StringMap<Bool>();
		var stack = [normalise(root)];
		while (stack.length > 0)
		{
			var directory = stack.pop();
			// A directory reached twice means a link cycles back up the tree, and
			// skipping it is what keeps the walk from running forever.
			if (visited.exists(directory)) continue;
			visited.set(directory, true);

			var names:Array<String> = readDirectory(directory);
			for (name in names)
			{
				var full = directory + "/" + name;
				if (isDirectory(full))
				{
					if (!skip.exists(name.toLowerCase())) stack.push(full);
					continue;
				}
				if (!StringTools.endsWith(name, ".meta")) continue;

				var text = readText(full);
				if (text == null) continue;
				var meta = MetaFile.parse(text);
				if (meta.guid != guid) continue;

				var assetPath = stripMetaSuffix(relativeTo(root, full));
				return AssetClassifier.build(meta, assetPath, AssetClassifier.originOf(assetPath));
			}
		}
		return null;
#else
		return null;
#end
	}

	/**
		Indexes every `.meta` under [root] into [index], returning how many were
		added.

		`Packages/` is indexed alongside `Assets/` when [ScanOptions.includePackages]
		is set, because packages hold assets that project files reference.
	**/
	public static function scanInto(index:AssetGuidIndex, root:String, ?options:ScanOptions):Int
	{
#if (sys || hxnodejs)
		if (index == null || root == null) return 0;
		var settings:ScanOptions = options == null ? {} : options;
		var includePackages = settings.includePackages == null ? true : settings.includePackages;
		var skip = buildSkip(settings.skip);

		var count = 0;
		var roots = scanRoots(root, settings);

		var visited = new StringMap<Bool>();
		for (start in roots)
		{
			if (!sys.FileSystem.exists(start) || !sys.FileSystem.isDirectory(start)) continue;
			count += indexTree(index, start, skip, visited, settings.onDirectory);
		}
		return count;
#else
		return 0;
#end
	}

#if (sys || hxnodejs)
	/** Walks one subtree, adding every asset found. **/
	static function indexTree(index:AssetGuidIndex, start:String, skip:StringMap<Bool>, visited:StringMap<Bool>,
			onDirectory:String->Void):Int
	{
		var count = 0;
		var stack = [normalise(start)];
		while (stack.length > 0)
		{
			var directory = stack.pop();
			// A directory already seen means a link cycles back; skipping it is what
			// stops the walk from running forever.
			if (visited.exists(directory)) continue;
			visited.set(directory, true);

			if (onDirectory != null) onDirectory(directory);

			var names:Array<String>;
			try
			{
				names = sys.FileSystem.readDirectory(directory);
			}
			catch (e:Dynamic)
			{
				// An unreadable directory is skipped rather than aborting the scan.
				continue;
			}

			for (name in names)
			{
				var full = directory + "/" + name;
				var isDirectory = false;
				try
				{
					isDirectory = sys.FileSystem.isDirectory(full);
				}
				catch (e:Dynamic)
				{
					continue;
				}

				if (isDirectory)
				{
					if (!skip.exists(name.toLowerCase())) stack.push(full);
					continue;
				}
				if (!StringTools.endsWith(name, ".meta")) continue;

				var text = readText(full);
				if (text == null) continue;
				var meta = MetaFile.parse(text);
				if (meta.guid == null) continue;

				var assetPath = stripMetaSuffix(relativeTo(index.projectRoot, full));
				var entry = AssetClassifier.build(meta, assetPath, AssetClassifier.originOf(assetPath));
				index.add(entry);
				count++;
			}
		}
		return count;
	}

	/**
		Names directly inside [directory], or an empty list when unreadable.

		An unreadable directory is skipped rather than aborting a whole scan, which
		matters on Windows where a directory can be locked by another process.
	**/
	public static function readDirectory(directory:String):Array<String>
	{
		try
		{
			return sys.FileSystem.readDirectory(directory);
		}
		catch (e:Dynamic)
		{
			return [];
		}
	}

	/** Reads [path] as text, or returns `null` when it cannot be read. **/
	public static function readText(path:String):String
	{
		try
		{
			return sys.io.File.getContent(path);
		}
		catch (e:Dynamic)
		{
			return null;
		}
	}

	/**
		True when [path] is an existing directory.

		One call, not `exists` followed by `isDirectory`: on Windows each of those is
		a separate filesystem round trip, and a directory walk calls this once per
		entry, so the extra check shows up directly in how long a refresh takes.
	**/
	public static function isDirectory(path:String):Bool
	{
		try
		{
			return sys.FileSystem.isDirectory(path);
		}
		catch (e:Dynamic)
		{
			return false;
		}
	}

	/** Directory names directly inside [path], or an empty list. **/
	public static function listDirectories(path:String):Array<String>
	{
		var out = [];
		try
		{
			for (name in sys.FileSystem.readDirectory(path))
			{
				if (sys.FileSystem.isDirectory(path + "/" + name)) out.push(name);
			}
		}
		catch (e:Dynamic) {}
		return out;
	}

	/** Last modified time of [path] in whole seconds, or -1 when unknown. **/
	public static function modifiedSeconds(path:String):Float
	{
		try
		{
			var info = sys.FileSystem.stat(path);
			return info == null ? -1 : Math.ffloor(info.mtime.getTime() / 1000);
		}
		catch (e:Dynamic)
		{
			return -1;
		}
	}

	/** Writes [text] to [path], replacing it atomically where the platform allows. **/
	public static function writeTextAtomic(path:String, text:String):Bool
	{
		var temporary = path + ".tmp";
		try
		{
			var parent = directoryOf(path);
			if (parent != null && !sys.FileSystem.exists(parent)) sys.FileSystem.createDirectory(parent);
			sys.io.File.saveContent(temporary, text);
			// Rename over the target so a crash mid-write cannot leave a half file
			// that the next run would read as a valid cache.
			if (sys.FileSystem.exists(path)) sys.FileSystem.deleteFile(path);
			sys.FileSystem.rename(temporary, path);
			return true;
		}
		catch (e:Dynamic)
		{
			try
			{
				if (sys.FileSystem.exists(temporary)) sys.FileSystem.deleteFile(temporary);
			}
			catch (ignored:Dynamic) {}
			return false;
		}
	}

	/** Directory part of [path], or `null` when there is none. **/
	public static function directoryOf(path:String):String
	{
		var slash = path.lastIndexOf("/");
		return slash <= 0 ? null : path.substring(0, slash);
	}
#else
	public static function readText(path:String):String return null;
	public static function readDirectory(directory:String):Array<String> return [];
	public static function collectDirectories(root:String, ?options:ScanOptions):Array<String> return [];
	public static function scanDirectoryInto(index:AssetGuidIndex, root:String, directory:String, found:Array<String>):Int return 0;
	public static function isDirectory(path:String):Bool return false;
	public static function listDirectories(path:String):Array<String> return [];
	public static function modifiedSeconds(path:String):Float return -1;
	public static function writeTextAtomic(path:String, text:String):Bool return false;
	public static function directoryOf(path:String):String return null;
#end

#if (sys || hxnodejs)
	/**
		Indexes the `.meta` files directly inside one directory, collecting the GUIDs.

		Used by an incremental refresh, which knows which directories changed and has
		already dropped their old entries. [found] is filled with the GUIDs indexed,
		so the cache can record which assets belong to which directory.
	**/
	public static function scanDirectoryInto(index:AssetGuidIndex, root:String, directory:String, found:Array<String>):Int
	{
		if (index == null || root == null || directory == null) return 0;
		var absolute = normalise(root) + "/" + normalise(directory);
		if (!isDirectory(absolute)) return 0;

		var count = 0;
		for (name in readDirectory(absolute))
		{
			if (!StringTools.endsWith(name, ".meta")) continue;
			var text = readText(absolute + "/" + name);
			if (text == null) continue;
			var meta = MetaFile.parse(text);
			if (meta.guid == null) continue;
			var assetPath = stripMetaSuffix(normalise(directory) + "/" + name);
			index.add(AssetClassifier.build(meta, assetPath, AssetClassifier.originOf(assetPath)));
			if (found != null) found.push(meta.guid);
			count++;
		}
		return count;
	}

	/**
		Every directory a scan would visit, as paths relative to [root].

		Used for cache validation: stamping these is what makes "nothing changed"
		provable without reading a single file. The order is stable (sorted), so a
		cache written by one run compares cleanly against the next.
	**/
	public static function collectDirectories(root:String, ?options:ScanOptions):Array<String>
	{
		if (root == null) return [];
		var settings:ScanOptions = options == null ? {} : options;
		var includePackages = settings.includePackages == null ? true : settings.includePackages;
		var skip = buildSkip(settings.skip);

		var out = [];
		var visited = new StringMap<Bool>();
		var roots = scanRoots(root, settings);

		for (start in roots)
		{
			if (!sys.FileSystem.exists(start) || !sys.FileSystem.isDirectory(start)) continue;
			var stack = [normalise(start)];
			while (stack.length > 0)
			{
				var directory = stack.pop();
				if (visited.exists(directory)) continue;
				visited.set(directory, true);
				out.push(relativeTo(root, directory));

				for (name in readDirectory(directory))
				{
					var full = directory + "/" + name;
					if (isDirectory(full) && !skip.exists(name.toLowerCase())) stack.push(full);
				}
			}
		}
		out.sort(Reflect.compare);
		return out;
	}
#end

	/**
		The directories a scan starts from, as absolute paths.

		`Assets/` and `Packages/` are the two places Unity keeps authored content.
		`Library/` is deliberately absent: it holds imported copies and the package
		cache, which is far larger than the sources and is not what project
		references point at.
	**/
	public static function scanRoots(root:String, ?options:ScanOptions):Array<String>
	{
		var settings:ScanOptions = options == null ? {} : options;
		var includePackages = settings.includePackages == null ? true : settings.includePackages;
		var base = normalise(root);
		var roots = [base + "/Assets"];
		if (includePackages) roots.push(base + "/Packages");
		return roots;
	}

	/** Forward slashes, no trailing separator. **/
	public static function normalise(path:String):String
	{
		var text = StringTools.replace(path, "\\", "/");
		while (StringTools.endsWith(text, "/"))
		{
			text = text.substr(0, text.length - 1);
		}
		return text;
	}

	/** [path] as seen from [root], or [path] itself when it is not below it. **/
	public static function relativeTo(root:String, path:String):String
	{
		if (root == null) return path;
		var base = normalise(root) + "/";
		var full = normalise(path);
		return StringTools.startsWith(full, base) ? full.substr(base.length) : full;
	}

	/** Strips the `.meta` suffix from [path]. **/
	public static function stripMetaSuffix(path:String):String
	{
		return StringTools.endsWith(path, ".meta") ? path.substr(0, path.length - 5) : path;
	}

#if (sys || hxnodejs)
	static function buildSkip(extra:Array<String>):StringMap<Bool>
	{
		var map = new StringMap<Bool>();
		for (name in DEFAULT_SKIP) map.set(name, true);
		if (extra != null)
		{
			for (name in extra) map.set(name.toLowerCase(), true);
		}
		return map;
	}
#end
}
