package;

import hxunity.prefab.UnityPrefab;

/**
	Round trip tests against real Unity files.

	The synthetic tests in [TestYaml] and [TestPrefab] pin down the format; these
	check the reader and writer against actual Unity output, which is the only way
	to be sure the wrapping and quoting rules match. The corpus comes from the
	first command line argument or from `CATSIM_ASSETS`; when neither names a
	directory the check is skipped so the suite runs anywhere.

	[limit] bounds how many files are checked, because a real project holds tens of
	thousands and the point here is to catch a format regression, not to audit the
	project. The standalone `tools.Validate` walks everything.
**/
class TestRoundTrip
{
	/** Extensions worth checking, one per Unity asset type. **/
	static var extensions = ["prefab", "asset", "unity", "mat", "controller", "anim", "meta"];

	/** Maximum number of files to check. **/
	public static var limit:Int = 150;

	/** Runs with an explicitly supplied corpus path, or the environment. **/
	public static function runWithCorpus(explicit:String):Void
	{
		corpus = explicit;
		run();
	}

	static var corpus:String = null;

	public static function run():Void
	{
		Assert.test("RoundTrip.corpus");

		var roots = [];
		if (corpus != null && sys.FileSystem.exists(corpus))
		{
			roots.push(corpus);
		}
		else
		{
			var fromEnvironment = Sys.getEnv("CATSIM_ASSETS");
			if (fromEnvironment != null && fromEnvironment.length > 0 && sys.FileSystem.exists(fromEnvironment))
			{
				roots.push(fromEnvironment);
			}
		}
		if (roots.length == 0)
		{
			TestMain.note("    skipped: no Unity project path given (pass one, or set CATSIM_ASSETS)");
			return;
		}

		// Spread the sample across the project rather than taking one directory,
		// so prefabs, materials, scenes and .meta files are all covered.
		var byExtension = new Map<String, Array<String>>();
		for (extension in extensions)
		{
			byExtension.set(extension, []);
		}
		var files = [];
		for (root in roots)
		{
			collect(root, byExtension, files, 40000);
		}

		var sample = [];
		var perExtension = Std.int(Math.max(1, limit / extensions.length));
		for (extension in extensions)
		{
			var candidates = byExtension.get(extension);
			candidates.sort(Reflect.compare);
			var taken = 0;
			var step = Std.int(Math.max(1, candidates.length / perExtension));
			var index = 0;
			while (index < candidates.length && taken < perExtension)
			{
				sample.push(candidates[index]);
				index += step;
				taken++;
			}
		}
		sample.sort(Reflect.compare);

		var identical = 0;
		var failures = [];
		var checked = 0;
		for (file in sample)
		{
			if (checked >= limit) break;
			checked++;
			var original = sys.io.File.getContent(file);
			try
			{
				var prefab = UnityPrefab.parse(original);
				if (prefab.emit() == original)
				{
					identical++;
				}
				else
				{
					failures.push(file);
				}
			}
			catch (e:Dynamic)
			{
				failures.push('$file: ${Std.string(e)}');
			}
		}

		TestMain.note('    checked $identical of $checked real Unity files, ${failures.length} differed');
		Assert.equals(failures.length, 0, 'every sampled real Unity file round trips'
			+ (failures.length == 0 ? "" : "\n    first failures:\n      " + failures.slice(0, 5).join("\n      ")));
		Assert.isTrue(identical > 0, "at least one file was checked");
	}

	/** Walks [path], grouping candidate files by extension. **/
	static function collect(path:String, byExtension:Map<String, Array<String>>, all:Array<String>, cap:Int):Void
	{
		if (all.length >= cap) return;
		if (!sys.FileSystem.exists(path)) return;
		if (sys.FileSystem.isDirectory(path))
		{
			for (name in sys.FileSystem.readDirectory(path))
			{
				if (name == ".git") continue;
				collect(path + "/" + name, byExtension, all, cap);
				if (all.length >= cap) return;
			}
			return;
		}
		var dot = path.lastIndexOf(".");
		if (dot < 0) return;
		var extension = path.substr(dot + 1);
		var bucket = byExtension.get(extension);
		if (bucket == null) return;
		bucket.push(path);
		all.push(path);
	}
}
