package hxunity.unity;

import haxe.Int64;

/**
	The header of a Unity `.meta` file, parsed without building a YAML tree.

	A `.meta` file is small and its useful part is at the top, so this reads the
	leading lines directly rather than running the full parser. That keeps a whole
	project walk cheap: on a 18,000 asset project the guid extraction is the single
	largest cost of building the index.
**/
class MetaFile
{
	/** How many lines are scanned before giving up on finding the fields. **/
	static inline var LINE_LIMIT = 400;

	/** `guid:` value, lowercased, or `null` when the file has none. **/
	public var guid(default, null):String;

	/**
		Importer section name, e.g. `TextureImporter`, or `null`.

		Only the first top level key whose name ends in `Importer` counts, because
		a `.meta` file may carry `labels:` before the importer section.
	**/
	public var importer(default, null):String;

	/** `mainObjectFileID` inside the importer section, or `null`. **/
	public var mainObjectFileId(default, null):Int64;

	/** True when the file declares `folderAsset: yes`. **/
	public var isFolder(default, null):Bool;

	function new(guid:String, importer:String, mainObjectFileId:Int64, isFolder:Bool)
	{
		this.guid = guid;
		this.importer = importer;
		this.mainObjectFileId = mainObjectFileId;
		this.isFolder = isFolder;
	}

	/**
		Reads the fields from a `.meta` file's text.

		Never throws: a file this does not understand yields nulls, because one odd
		`.meta` must not abort a whole project scan. Only the leading lines are
		examined, which is why a caller may pass the text of a large file without
		splitting all of it first.
	**/
	public static function parse(text:String):MetaFile
	{
		var guid:String = null;
		var importer:String = null;
		var mainId:Int64 = null;
		var isFolder = false;
		var inImporter = false;
		var indentationLimit = 0;
		var lines = 0;

		var start = 0;
		var length = text.length;
		while (start <= length && lines < LINE_LIMIT)
		{
			var end = text.indexOf("\n", start);
			if (end < 0) end = length;
			var line = text.substring(start, end);
			if (StringTools.endsWith(line, "\r")) line = line.substr(0, line.length - 1);
			start = end + 1;
			lines++;

			var trimmed = StringTools.trim(line);
			if (trimmed.length == 0) continue;
			if (trimmed.charAt(0) == "#") continue;

			var indented = line.charCodeAt(0) == " ".code || line.charCodeAt(0) == "\t".code;
			if (!indented)
			{
				// A top level key. Anything ending in `Importer` opens the importer
				// section; every other top level key closes it, which is what keeps
				// a later `labels:` key from being read as importer content.
				var key = trimmed;
				var colon = key.indexOf(":");
				if (colon >= 0) key = key.substring(0, colon);
				key = StringTools.trim(key);

				if (key == "guid")
				{
					guid = valueOf(trimmed, "guid");
				}
				else if (key == "folderAsset")
				{
					var value = valueOf(trimmed, "folderAsset");
					isFolder = value != null && value.toLowerCase() == "yes";
				}

				if (StringTools.endsWith(key, "Importer"))
				{
					if (importer == null) importer = key;
					inImporter = true;
					indentationLimit = -1;
				}
				else
				{
					inImporter = false;
				}
				continue;
			}

			// An indented line: only the importer section is inspected, and only its
			// own top level keys, so a nested block cannot supply a false value.
			if (inImporter && mainId == null)
			{
				if (indentationLimit < 0) indentationLimit = countIndent(line);
				if (countIndent(line) == indentationLimit)
				{
					var trimmedKey = StringTools.trim(line);
					if (StringTools.startsWith(trimmedKey, "mainObjectFileID:"))
					{
						var value = valueOf(trimmedKey, "mainObjectFileID");
						var parsed = parseInt64(value);
						if (parsed != null) mainId = parsed;
					}
				}
			}
		}

		return new MetaFile(guid == null ? null : guid.toLowerCase(), importer, mainId, isFolder);
	}

	/** Leading whitespace width of [line], counting a tab as two. **/
	static function countIndent(line:String):Int
	{
		var width = 0;
		var i = 0;
		while (i < line.length)
		{
			var c = line.charCodeAt(i);
			if (c == " ".code) width++;
			else if (c == "\t".code) width += 2;
			else break;
			i++;
		}
		return width;
	}

	/** Value after `key:` in [line], trimmed, or `null` when empty. **/
	static function valueOf(line:String, key:String):String
	{
		var value = StringTools.trim(line.substring(key.length + 1));
		return value.length == 0 ? null : value;
	}

	/** Local 64 bit parse, so this file needs no dependency on the YAML layer. **/
	static function parseInt64(text:String):Int64
	{
		if (text == null) return null;
		var trimmed = StringTools.trim(text);
		if (trimmed.length == 0) return null;
		try
		{
			return Int64.parseString(trimmed);
		}
		catch (e:Dynamic)
		{
			return null;
		}
	}

	public function toString():String
	{
		return 'MetaFile(guid=$guid importer=$importer main=${mainObjectFileId == null ? "-" : Int64.toStr(mainObjectFileId)} folder=$isFolder)';
	}
}
