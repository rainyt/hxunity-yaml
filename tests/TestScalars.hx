package;

import hxunity.yaml.Scalars;
import hxunity.yaml.ScalarKind;
import hxunity.yaml.YamlScalar;

/** Tests for scalar interpretation and quoting rules. **/
class TestScalars
{
	public static function run():Void
	{
		numbers();
		bools();
		nulls();
		quoting();
		scalarNodes();
	}

	static function numbers():Void
	{
		Assert.test("Scalars.numbers");
		Assert.isTrue(Scalars.isNumber("0"), "0 is a number");
		Assert.isTrue(Scalars.isNumber("-0"), "-0 is a number");
		Assert.isTrue(Scalars.isNumber("1.5"), "1.5 is a number");
		Assert.isTrue(Scalars.isNumber("-0.02"), "-0.02 is a number");
		Assert.isTrue(Scalars.isNumber(".5"), ".5 is a number");
		Assert.isTrue(Scalars.isNumber("1e-05"), "1e-05 is a number");
		Assert.isTrue(Scalars.isNumber("1E+10"), "1E+10 is a number");
		Assert.isTrue(Scalars.isNumber("0.7071068"), "0.7071068 is a number");

		Assert.isFalse(Scalars.isNumber("10f"), "10f is not a plain number");
		Assert.isFalse(Scalars.isNumber("abc"), "abc is not a number");
		Assert.isFalse(Scalars.isNumber(""), "empty text is not a number");
		Assert.isFalse(Scalars.isNumber("1.2.3"), "1.2.3 is not a number");
		Assert.isFalse(Scalars.isNumber("--1"), "--1 is not a number");
		Assert.isFalse(Scalars.isNumber("1e"), "1e is not a number");
		Assert.isFalse(Scalars.isNumber("0x10"), "0x10 is not a Unity number");

		Assert.equals(Scalars.tryFloat("-0.02"), -0.02, "tryFloat reads -0.02");
		Assert.equals(Scalars.tryInt("42"), 42, "tryInt reads 42");
		Assert.equals(Scalars.tryInt("2147483648"), null, "tryInt refuses a value past 32 bits");
		Assert.notNull(Scalars.tryInt64("8601872862307532784"), "tryInt64 reads a prefab file id");
		Assert.equals(haxe.Int64.toStr(Scalars.tryInt64("8601872862307532784")), "8601872862307532784", "file id survives exactly");
		Assert.equals(haxe.Int64.toStr(Scalars.tryInt64("-8221572380872265284")), "-8221572380872265284", "negative file id survives");
		Assert.equals(Scalars.tryInt64("10f"), null, "tryInt64 rejects 10f");
	}

	static function bools():Void
	{
		Assert.test("Scalars.bools");
		Assert.equals(Scalars.tryBool("1"), true, "Unity writes booleans as 1/0, so 1 is true");
		Assert.equals(Scalars.tryBool("0"), false, "0 is false");
		Assert.equals(Scalars.tryBool("true"), true, "true is a bool");
		Assert.equals(Scalars.tryBool("yes"), true, "yes is a YAML 1.1 bool, used by .meta files");
		Assert.equals(Scalars.tryBool("no"), false, "no is a YAML 1.1 bool");
		Assert.equals(Scalars.tryBool("Off"), false, "Off is a YAML 1.1 bool");
		Assert.equals(Scalars.tryBool("maybe"), null, "maybe is not a bool");
		Assert.equals(Scalars.tryBool("2"), null, "2 is not a bool");
	}

	static function nulls():Void
	{
		Assert.test("Scalars.nulls");
		Assert.isTrue(Scalars.isNullText(""), "empty text is null");
		Assert.isTrue(Scalars.isNullText("~"), "~ is null");
		Assert.isTrue(Scalars.isNullText("null"), "null is null");
		Assert.isFalse(Scalars.isNullText("Nullish"), "Nullish is not null");
	}

	static function quoting():Void
	{
		Assert.test("Scalars.quoting");
		Assert.isFalse(Scalars.needsQuoting("alex_fat"), "a plain name needs no quoting");
		Assert.isFalse(Scalars.needsQuoting("-0.02"), "a negative number needs no quoting");
		Assert.isFalse(Scalars.needsQuoting("0.7071068"), "a float needs no quoting");
		Assert.isTrue(Scalars.needsQuoting("- "), "a lone dash needs quoting");
		Assert.isTrue(Scalars.needsQuoting("yes"), "yes must be quoted to stay a string");
		Assert.isTrue(Scalars.needsQuoting("~"), "~ must be quoted to stay a string");
		Assert.isTrue(Scalars.needsQuoting(" leading"), "leading space needs quoting");
		Assert.isTrue(Scalars.needsQuoting("trailing "), "trailing space needs quoting");
		Assert.isTrue(Scalars.needsQuoting("a: b"), "a colon space needs quoting");
		Assert.isTrue(Scalars.needsQuoting("a #b"), "a hash after a space needs quoting");
		Assert.isTrue(Scalars.needsQuoting("{brace}"), "a leading flow indicator needs quoting");
		Assert.isTrue(Scalars.needsQuoting("with\ttab"), "a tab needs quoting");
	}

	static function scalarNodes():Void
	{
		Assert.test("Scalars.scalarNodes");
		var empty = new YamlScalar("", ScalarKind.Plain);
		Assert.isTrue(empty.isNull(), "an empty plain scalar is null");
		var quotedEmpty = new YamlScalar("", ScalarKind.SingleQuoted);
		Assert.isFalse(quotedEmpty.isNull(), "a quoted empty scalar is an empty string, not null");
		var tagged = new YamlScalar("114", ScalarKind.Plain, 0, -1, "!u!114");
		Assert.equals(tagged.tag, "!u!114", "an explicit tag is kept");
		Assert.equals(haxe.Int64.toStr(new YamlScalar("8601872862307532784", ScalarKind.Plain).toInt64()), "8601872862307532784",
			"toInt64 returns the exact id");
	}
}
