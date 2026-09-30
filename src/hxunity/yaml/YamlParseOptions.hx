package hxunity.yaml;

/** Options controlling how [YamlParser] builds its node tree. **/
typedef YamlParseOptions = {
	/**
		Keeps `\r\n` line endings in reported positions and disables the automatic
		BOM strip. Reading is line based and works with either ending, so this
		only affects what the position information refers to.
	**/
	@:optional var keepCarriageReturns:Bool;

	/**
		Rejects duplicate keys in a mapping instead of keeping both entries.

		Off by default because Unity never emits duplicates and a permissive
		reader is more useful when inspecting a hand edited file.
	**/
	@:optional var rejectDuplicateKeys:Bool;

	/** Records line/column on every node. Costs one field write per node. **/
	@:optional var trackPositions:Bool;

	/**
		Resolves `&anchor` / `*alias` pairs so an aliased node carries the anchored
		node's text. Unity anchors documents rather than values, so this is off by
		default and exists for general YAML input.
	**/
	@:optional var resolveAliases:Bool;
}
