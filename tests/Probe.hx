package;

/**
	Debug runner: runs one test group, or one named sub test of a group.

	Used to localise a hang or a crash without starting the whole suite:

	  HXU_GROUP=unity HXU_ONLY=documentSet neko build/probe.n
**/
class Probe
{
	static function main()
	{
		var group = Sys.getEnv("HXU_GROUP");
		if (group == null || group.length == 0) group = "scalars";
		Sys.println("group=" + group + " only=" + Sys.getEnv("HXU_ONLY"));
		switch (group)
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
		Sys.println("done: passed=" + Assert.passed + " failures=" + Assert.failures.length);
		for (failure in Assert.failures) Sys.println("  " + failure);
	}
}
