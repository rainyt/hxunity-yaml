package;

/** Scratch runner: executes one hard coded test group for `--interp`. **/
class ProbeRun
{
	static function main()
	{
		var which = Sys.getEnv("GROUP");
		if (which == null) which = "scalars";
		Sys.println("running " + which);
		switch (which)
		{
			case "scalars":
				TestScalars.run();
			case "yaml":
				TestYaml.run();
			case "lexer":
				TestYaml.lexer();
			case "unity":
				TestUnity.run();
			case "prefab":
				TestPrefab.run();
			case "roundtrip":
				TestRoundTrip.run();
			default:
				Sys.println("unknown group");
		}
		Sys.println("done, passed=" + Assert.passed + " failures=" + Assert.failures.length);
		for (failure in Assert.failures) Sys.println("  " + failure);
	}
}
