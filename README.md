# Git on z/OS
To use Git on z/OS, source the .env file as follows:
`. ./.env`

## Encoding considerations
Git on z/OS leverages the git .gitattributes support to enable support for various encodings, documented [here](https://git-scm.com/docs/gitattributes). 
.gitattributes can be specified globally, or repositories to determine the encoding of working tree files.

Specifically, the `working-tree-encoding` attribute can be used to determine the working tree encoding. For example,
to convert all files from the internal UTF-8 encoding to IBM-1047, you can specify the following working-tree-encoding:
```
* text working-tree-encoding=IBM-1047
```
Git on z/OS will also tag files as ibm-1047 on checkout. 

If no encoding is specified, the default UTF-8 encoding is used and all files are tagged as ISO8859-1. 

To add specify binary encoding, you can use the binary attribute as follows:
```
*.png binary
```
This will tag all `*.png` files as binary.

You can specify multiple working-tree-encoding attributes, where the later attributes overrides the initial attributes in case of an overlap.
```
* text working-tree-encoding=IBM-1047
*.png binary
```

When adding files, you need to make sure that the z/OS file tag matches the working-tree-encoding. Otherwise, you may encounter an error.

NOTE: Git on z/OS does not currently support adding `untagged` files.
