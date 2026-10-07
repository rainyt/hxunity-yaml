package;

/**
	Test runner for hxunity-yaml.

	Run with:
	  haxe -cp src -cp tests --run TestMain [unity-project-path] [--files N]

	Passing a Unity project path (or setting `CATSIM_ASSETS`) additionally runs
	the round trip tests against that project's real files. `--files N` bounds how
	many of them are checked, which keeps the suite quick on a large project.
**/
class TestMain
{
	/** Console output captured while a group runs, attached to a failure. **/
	static var captured:StringBuf = new StringBuf();

	/** True while a group's output is being buffered. **/
	static var buffering:Bool = false;

	public static function main()
	{
		var arguments = Sys.args();
		var corpus:String = null;
		var limit = 150;
		var index = 0;
		while (index < arguments.length)
		{
			var argument = arguments[index];
			if (argument == "--files" && index + 1 < arguments.length)
			{
				index++;
				var parsed = Std.parseInt(arguments[index]);
				if (parsed != null) limit = parsed;
			}
			else if (argument != null && argument.length > 0 && argument.charAt(0) != "-")
			{
				corpus = argument;
			}
			index++;
		}

		Sys.println("hxunity-yaml test suite");
		Sys.println("");

		run("Scalars", TestScalars.run);
		run("Yaml", TestYaml.run);
		run("Yaml lexer", TestYaml.lexer);
		run("Unity", TestUnity.run);
		run("Prefab", TestPrefab.run);
		run("Prefab instance", TestPrefabInstance.run);
		run("Guid index", TestGuidIndex.run);
		TestRoundTrip.limit = limit;
		run("Round trip", TestRoundTrip.runWithCorpus.bind(corpus));

		Sys.println("");
		if (Assert.failures.length == 0)
		{
			Sys.println('OK: ${Assert.passed} assertions passed');
			Sys.exit(0);
		}

		Sys.println('FAILED: ${Assert.failures.length} of ${Assert.passed + Assert.failures.length} assertions failed');
		Sys.println("");
		for (failure in Assert.failures)
		{
			Sys.println("  " + failure);
			Sys.println("");
		}
		Sys.exit(1);
	}

	/**
		Runs one group, reporting it before and after, and recording a failure.

		A group stops at its first failed assertion, because the rest of that group
		usually depends on the state the failed assertion was checking. Output the
		group prints is buffered and only flushed when the group finishes, so the
		normal run stays readable while a failure still carries its diagnostics.
	**/
	static function run(label:String, body:Void->Void):Void
	{
		Sys.print("  " + label + " ... ");
		var before = Assert.passed;
		var failuresBefore = Assert.failures.length;
		captured = new StringBuf();
		buffering = true;
		var error:String = null;
		try
		{
			body();
		}
		catch (failure:AssertionFailure)
		{
			Assert.failures.push(failure.detail);
		}
		catch (e:Dynamic)
		{
			error = 'unexpected error in ${Assert.testName()}: ${Std.string(e)}';
			Assert.failures.push(error);
		}
		buffering = false;
		var text = captured.toString();
		captured = new StringBuf();

		if (Assert.failures.length > failuresBefore)
		{
			Sys.println("FAIL");
			Sys.print(text);
			Sys.println("    " + Assert.failures[Assert.failures.length - 1].split("\n").join("\n    "));
		}
		else
		{
			Sys.println('ok  (${Assert.passed - before} assertions)');
			Sys.print(text);
		}
	}

	/** Prints progress; buffered and flushed with the group's result. **/
	public static function note(message:String):Void
	{
		if (buffering)
		{
			captured.add(message);
			captured.add("\n");
		}
		else
		{
			Sys.println(message);
		}
	}
}
