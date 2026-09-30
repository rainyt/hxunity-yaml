package;

/**
	Minimal assertion helpers for the test runner.

	The library is verified with `haxe --interp` and no test framework, so that
	running the suite needs nothing beyond a Haxe install.

	A failed assertion throws. The runner catches it, records it against the test
	that was running, and carries on with the next test, so one broken expectation
	reports itself instead of crashing the run at the next line that dereferences
	whatever the assertion was about.
**/
class Assert
{
	/** Number of assertions that passed. **/
	public static var passed:Int = 0;

	/** Assertion failures, formatted for the summary. **/
	public static var failures:Array<String> = [];

	static var currentTest:String = "<none>";

	/** Names the test the following assertions belong to. **/
	public static function test(name:String):Void
	{
		currentTest = name;
	}

	/** Name of the test currently running. **/
	public static function testName():String
	{
		return currentTest;
	}

	static function record(ok:Bool, message:String):Void
	{
		if (ok)
		{
			passed++;
			return;
		}
		throw new AssertionFailure(currentTest, message);
	}

	/** Asserts [condition] is true. **/
	public static function isTrue(condition:Bool, message:String):Void
	{
		record(condition, message + " (expected true, got false)");
	}

	/** Asserts [condition] is false. **/
	public static function isFalse(condition:Bool, message:String):Void
	{
		record(!condition, message + " (expected false, got true)");
	}

	/** Asserts two values are equal. **/
	public static function equals(actual:Dynamic, expected:Dynamic, message:String):Void
	{
		record(actual == expected, message + ' (expected ${render(expected)}, got ${render(actual)})');
	}

	/** Asserts two strings are equal, showing both with visible delimiters. **/
	public static function stringEquals(actual:String, expected:String, message:String):Void
	{
		if (actual == expected)
		{
			passed++;
			return;
		}
		var where = firstDifference(actual, expected);
		throw new AssertionFailure(currentTest, '$message\n' + '    expected: ${visible(expected)}\n'
			+ '    actual:   ${visible(actual)}\n' + '    first difference at character $where');
	}

	/** Asserts a string contains [needle]. **/
	public static function contains(haystack:String, needle:String, message:String):Void
	{
		record(haystack != null && haystack.indexOf(needle) >= 0, message + ' (looking for ${visible(needle)} in ${visible(haystack)})');
	}

	/** Asserts a string does not contain [needle]. **/
	public static function notContains(haystack:String, needle:String, message:String):Void
	{
		record(haystack == null || haystack.indexOf(needle) < 0, message + ' (unexpectedly found ${visible(needle)})');
	}

	/** Asserts [value] is null. **/
	public static function isNull(value:Dynamic, message:String):Void
	{
		record(value == null, message + " (expected null, got " + render(value) + ")");
	}

	/** Asserts [value] is not null. **/
	public static function notNull(value:Dynamic, message:String):Void
	{
		record(value != null, message + " (expected a value, got null)");
	}

	/**
		Asserts that [body] throws.

		Returns the thrown value so the caller can check the message. A call that
		throws [AssertionFailure] is rethrown, because that is a failed assertion
		inside the body rather than the expected exception.
	**/
	public static function throws(body:Void->Void, message:String):Dynamic
	{
		try
		{
			body();
		}
		catch (failure:AssertionFailure)
		{
			throw failure;
		}
		catch (e:Dynamic)
		{
			passed++;
			return e;
		}
		throw new AssertionFailure(currentTest, message + " (nothing was thrown)");
	}

	static function firstDifference(a:String, b:String):Int
	{
		var max = a.length < b.length ? a.length : b.length;
		for (i in 0...max)
		{
			if (a.charCodeAt(i) != b.charCodeAt(i)) return i;
		}
		return max;
	}

	static function visible(text:String):String
	{
		if (text == null) return "null";
		var escaped = text.split("\r").join("\\r").split("\n").join("\\n").split("\t").join("\\t");
		if (escaped.length > 220) escaped = escaped.substr(0, 220) + "...";
		return '"' + escaped + '"';
	}

	static function render(value:Dynamic):String
	{
		if (value == null) return "null";
		if (Std.isOfType(value, String)) return visible(cast value);
		return Std.string(value);
	}
}

