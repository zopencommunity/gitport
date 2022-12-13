# Git on z/OS
To use Git on z/OS, source the .env file as follows:
`. ./.env`

## Encoding considerations
Git on z/OS leverages Git's `.gitattributes` support to enable support for various encodings, documented [here](https://git-scm.com/docs/gitattributes). 
`.gitattributes` can be specified globally, or locally in repositories to determine the encoding of working tree files.

### Working-tree-encoding
The `working-tree-encoding` attribute can be used to determine the working tree encoding. For example,
to convert all files from Git's internal UTF-8 encoding to IBM-1047, you can specify the following working-tree-encoding in your .gitattributes file:
```
* text working-tree-encoding=IBM-1047
```
This will result in Git on z/OS tagging all files as IBM-1047 on checkout. 

If no encoding is specified, the default UTF-8 encoding is used and all files are tagged as ISO8859-1. 

To find out all of the supported encodings, run `iconv -l`.

### Binary files
To specify a binary encoding, you can use the binary attribute as follows:
```
*.png binary
```
This will tag all `*.png` files as binary.

### Multiple encodings
You can specify multiple working-tree-encoding attributes, where the later attributes overrides the initial attributes in case of an overlap.
```
* text working-tree-encoding=IBM-1047
*.png binary
```

### Gotchas
When adding files, you need to make sure that the z/OS file tag matches the working-tree-encoding. Otherwise, you may encounter an error.

NOTE: Git on z/OS does not currently support adding `untagged` files.

### Comparison to Rocket Software's Git
Rocket Software implemented `zos-working-tree-encoding`, including it's synonym `working-tree-encoding`. Git on z/OS does not support zos-working-tree-encoding.
Furthermore, Rocket Software implemented zos-working-tree-encoding from scratch, while Git on z/OS leverages the Git's official working-tree-encoding support.

Binary files are also handled differently. With Rocket's Git, `zos-working-tree-encoding=BINARY` must be specified to ensure a file is tagged as binary. 
Git on z/OS leverages the `binary` keyword, which is officially supported by Git.
