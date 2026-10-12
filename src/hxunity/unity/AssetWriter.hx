package hxunity.unity;

/**
	Writing assets to disk, with the conventions Unity's own tooling assumes.

	Three of those conventions are worth stating, because each one fails
	silently when broken:

	* **every asset needs its `.meta` next to it, with the same name plus
	  `.meta`**. The index derives one from the other
	  ([metaPathOf] / [assetPathOf]), so a name that differs by one character
	  breaks the whole chain: the asset is invisible to references and Unity
	  imports it as a second copy.
	* **a `.meta` file is written with LF endings, UTF-8, no BOM and one trailing
	  newline.** A UTF-8 BOM in front of `fileFormatVersion:` makes Unity fail to
	  read the GUID, which presents as every reference to that asset going
	  missing. [saveText] writes that shape and nothing else.
	* **writes are atomic** — a temporary file renamed over the target. A half
	  written `.mat` or PNG gets imported as a corrupt asset, and the editor's
	  reader sees truncated YAML.

	On a target without `sys` every write returns false rather than failing to
	compile, the same way [ProjectFiles] behaves, so the rest of the library still
	builds for the browser.
**/
class AssetWriter
{
	/** Suffix Unity appends to an asset's path to get its `.meta` path. **/
	public static inline var META_SUFFIX = ".meta";

	/**
		Creates [path] and every missing parent directory.

		Returns false when the path cannot be created, which on a locked or
		read-only volume is the first sign an export is about to fail.
	**/
	public static function ensureDirectory(path:String):Bool
	{
		return ProjectFiles.ensureDirectory(path);
	}

	/** True when [path] exists, as a file or as a directory. **/
	public static function exists(path:String):Bool
	{
		return ProjectFiles.exists(path);
	}

	/**
		Writes [text] as a Unity asset file.

		Line endings are normalised to LF and exactly one trailing newline is
		added, so the same call on Windows and macOS produces the same bytes.
		An existing file is replaced atomically.
	**/
	public static function saveText(path:String, text:String):Bool
	{
		if (path == null) return false;
		return ProjectFiles.writeTextAtomic(path, normaliseText(text));
	}

	/** Writes [bytes], atomically, with no transformation at all. **/
	public static function saveBytes(path:String, bytes:haxe.io.Bytes):Bool
	{
		if (path == null) return false;
		return ProjectFiles.writeBytesAtomic(path, bytes);
	}

	/** [text] with LF line endings and exactly one trailing newline. **/
	public static function normaliseText(text:String):String
	{
		var out = text == null ? "" : text;
		if (out.indexOf("\r") >= 0) out = out.split("\r\n").join("\n").split("\r").join("\n");
		if (!StringTools.endsWith(out, "\n")) out += "\n";
		return out;
	}

	/**
		The `.meta` path of the asset at [assetPath].

		Unity's rule is a suffix, not a rename: `Assets/Art/hand.png` is described
		by `Assets/Art/hand.png.meta`.
	**/
	public static function metaPathOf(assetPath:String):String
	{
		if (assetPath == null) return null;
		return StringTools.endsWith(assetPath, META_SUFFIX) ? assetPath : assetPath + META_SUFFIX;
	}

	/** The asset path a `.meta` file at [metaPath] describes. **/
	public static function assetPathOf(metaPath:String):String
	{
		if (metaPath == null) return null;
		return StringTools.endsWith(metaPath, META_SUFFIX) ? metaPath.substr(0, metaPath.length - META_SUFFIX.length) : metaPath;
	}

	/** True when [path] is a `.meta` file's path. **/
	public static function isMetaPath(path:String):Bool
	{
		return path != null && StringTools.endsWith(path, META_SUFFIX);
	}

	/**
		Replaces the characters a file name cannot carry.

		Unity refuses `/`, `\`, `:`, `*`, `?`, `"`, `<`, `>` and `|` in an asset
		name on every platform it supports, so cleaning for the strictest of them
		keeps an export portable. Leading dots go too: a name starting with `.`
		is hidden on macOS and Linux, and Unity skips it during a scan.

		Control characters are removed rather than replaced, and leading or
		trailing spaces and trailing dots are trimmed because Windows silently
		drops them — which would rename the asset behind the caller's back.
	**/
	public static function sanitiseName(name:String):String
	{
		if (name == null) return "Asset";
		var sb = new StringBuf();
		var length = name.length;
		for (i in 0...length)
		{
			var code = name.charCodeAt(i);
			var c = name.charAt(i);
			if (code < 32 || code == 127) continue;
			sb.add("\\/:*?\"<>|".indexOf(c) >= 0 ? "_" : c);
		}
		var text = StringTools.trim(sb.toString());
		while (text.length > 0 && text.charAt(0) == ".") text = text.substr(1);
		while (StringTools.endsWith(text, ".")) text = text.substr(0, text.length - 1);
		text = StringTools.trim(text);
		if (text.length == 0) return "Asset";
		// Windows' reserved device names (`CON`, `NUL`, `COM1`, ...) are left
		// alone. They cannot be created on Windows, where the write then fails
		// loudly rather than silently producing an asset nobody can commit, and
		// renaming them would be wrong on macOS and Linux, where they are ordinary
		// names.
		return text;
	}

	/**
		A file name in [directory] that no existing file uses.

		The first candidate is `base.ext`; when that is taken the call appends
		` 1`, ` 2`, ... which is the scheme Unity's own asset creation uses. The
		comparison is case insensitive, because on macOS and Windows
		`Hand.png` and `hand.png` are the same file.

		The returned value is a **file name**, not a path; [directory] is only
		read to see what is already there.
	**/
	public static function uniqueFileName(directory:String, baseName:String, extension:String):String
	{
		var base = sanitiseName(baseName);
		var suffix = extension == null || extension.length == 0 ? "" : (StringTools.startsWith(extension, ".") ? extension : "." + extension);
		var taken = existingNames(directory);
		var candidate = base + suffix;
		var attempt = 0;
		while (taken.exists(candidate.toLowerCase()) && attempt < 10000)
		{
			attempt++;
			candidate = base + " " + attempt + suffix;
		}
		return candidate;
	}

	/** A full path built from [directory], [baseName] and [extension], made unique. **/
	public static function uniquePath(directory:String, baseName:String, extension:String):String
	{
		var name = uniqueFileName(directory, baseName, extension);
		if (directory == null || directory.length == 0) return name;
		return ProjectFiles.normalise(directory) + "/" + name;
	}

	/** Lowercased names directly inside [directory], for a uniqueness check. **/
	static function existingNames(directory:String):Map<String, Bool>
	{
		var out = new Map<String, Bool>();
		if (directory == null) return out;
		for (name in ProjectFiles.readDirectory(directory))
		{
			out.set(name.toLowerCase(), true);
		}
		return out;
	}
}
