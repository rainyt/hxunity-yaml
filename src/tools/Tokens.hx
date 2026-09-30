package;

import hxunity.yaml.YamlLexer;
import hxunity.yaml.YamlToken;

/** Prints the token stream of a Unity YAML file. **/
class Tokens
{
	static function main()
	{
		var args = Sys.args();
		var text = sys.io.File.getContent(args[0]);
		var from = args.length > 1 ? Std.parseInt(args[1]) : 1;
		var to = args.length > 2 ? Std.parseInt(args[2]) : 1000;
		var lexer = new YamlLexer(text);
		while (true)
		{
			var token = lexer.next();
			if (token.type == Eof) break;
			if (token.line < from || token.line > to) continue;
			Sys.println("line=" + token.line + " col=" + token.column + " indent=" + token.indent + "  " + token.type + "  '" + token.text + "'"
				+ (token.alias != null ? " alias=" + token.alias : ""));
		}
	}
}
