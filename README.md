# Git on z/OS
To use Git on z/OS, source the .env file as follows:
`. ./.env`

## Encoding considerations
Git on z/OS leverages Git's `.gitattributes` support to enable support for various encodings, documented [here](https://git-scm.com/docs/gitattributes). 
`.gitattributes` can be specified globally, or locally in repositories to determine the encoding of working tree files.

### Working-tree-encoding
The `working-tree-encoding` attribute can be used to determine the working tree encoding. For example,
to convert all files from Git's internal UTF-8 encoding to IBM-1047, you can specify the following working-tree-encoding:
```
* text working-tree-encoding=IBM-1047
```
This will also result in Git on z/OS tagging all files as ibm-1047 on checkout. 

If no encoding is specified, the default UTF-8 encoding is used and all files are tagged as ISO8859-1. 

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
