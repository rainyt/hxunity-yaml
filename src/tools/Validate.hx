package;

import haxe.Int64;
import hxunity.yaml.UnityDocumentSet;
import hxunity.yaml.YamlParseOptions;

/**
	Round trip validator.

	Reads a Unity YAML file (or every file under a directory), parses it, writes
	it straight back and compares the result byte for byte with the original.
	Any difference is reported with the first mismatching line, which is the
	fastest way to find a formatting rule the writer has not matched yet.

	Build with:
	  haxe -cp src -cp src/tools -main Validate --interp <path> [--limit N] [--show N]
**/
class Validate
{
	static function main()
	{
		var args = Sys.args();
		var paths = [];
		var limit = 100000;
		var show = 3;
		var i = 0;
		while (i < args.length)
		{
			switch (args[i])
			{
				case "--limit":
					i++;
					limit = Std.parseInt(args[i]);
				case "--show":
					i++;
					show = Std.parseInt(args[i]);
				default:
					paths.push(args[i]);
			}
			i++;
		}
		if (paths.length == 0)
		{
			Sys.println("usage: Validate <file-or-directory> [--limit N] [--show N]");
			Sys.exit(1);
		}

		var files = [];
		for (path in paths)
		{
			collect(path, files);
		}
		files.sort(Reflect.compare);

		var total = 0;
		var passed = 0;
		var failed = 0;
		var errored = 0;
		var shown = 0;
		var firstFailures = [];

		for (file in files)
		{
			if (total >= limit) break;
			total++;
			var original:String;
			try
			{
				original = sys.io.File.getContent(file);
			}
			catch (e:Dynamic)
			{
				continue;
			}
			var emitted:String;
			try
			{
				var set = UnityDocumentSet.parse(original, {trackPositions: true});
				emitted = set.emit();
			}
			catch (e:Dynamic)
			{
				errored++;
				if (shown < show)
				{
					shown++;
					Sys.println("ERROR " + file);
					Sys.println("  " + Std.string(e));
					Sys.println(haxe.CallStack.toString(haxe.CallStack.exceptionStack()));
				}
				firstFailures.push(file);
				continue;
			}
			if (emitted == original)
			{
				passed++;
				continue;
			}
			failed++;
			firstFailures.push(file);
			if (shown < show)
			{
				shown++;
				report(file, original, emitted);
			}
		}

		Sys.println("");
		Sys.println("files=" + total + " identical=" + passed + " different=" + failed + " errors=" + errored);
		if (failed + errored > 0)
		{
			Sys.println("first failing files:");
			for (f in firstFailures)
			{
				if (firstFailures.indexOf(f) > 20) break;
				Sys.println("  " + f);
			}
			Sys.exit(2);
		}
	}

	static function collect(path:String, out:Array<String>):Void
	{
		if (sys.FileSystem.isDirectory(path))
		{
			for (name in sys.FileSystem.readDirectory(path))
			{
				if (name == ".git") continue;
				collect(path + "/" + name, out);
			}
			return;
		}
		var ext = path.substr(path.lastIndexOf(".") + 1);
		switch (ext)
		{
			case "prefab", "asset", "unity", "mat", "controller", "anim", "meta", "playable", "overrideController", "yaml", "yml":
				out.push(path);
			default:
		}
	}

	/** Prints the first differing line of a failed round trip. **/
	static function report(file:String, original:String, emitted:String):Void
	{
		var a = hxunity.yaml.Strings.splitLines(original);
		var b = hxunity.yaml.Strings.splitLines(emitted);
		var max = a.length > b.length ? a.length : b.length;
		Sys.println("DIFF " + file + "  (original " + a.length + " lines, emitted " + b.length + " lines)");
		var reported = 0;
		for (i in 0...max)
		{
			var la = i < a.length ? a[i] : "<missing>";
			var lb = i < b.length ? b[i] : "<missing>";
			if (la == lb) continue;
			Sys.println("  line " + (i + 1) + ":");
			Sys.println("    want |" + la + "|");
			Sys.println("    got  |" + lb + "|");
			reported++;
			if (reported >= 4) break;
		}
	}
}
