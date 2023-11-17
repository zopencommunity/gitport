[![Automatic version updates](https://github.com/ZOSOpenTools/gitport/actions/workflows/bump.yml/badge.svg)](https://github.com/ZOSOpenTools/gitport/actions/workflows/bump.yml)

# Git on z/OS
Git is a popular version control system that is widely used in the open source community. 

## Pre-requisites
Git on z/OS has the following dependencies:
* bash - https://github.com/ZOSOpenTools/bashport/releases
* perl - https://github.com/ZOSOpenTools/perlport/releases
* less - (default pager) //github.com/ZOSOpenTools/lessport/releases
* ncurses - https://github.com/ZOSOpenTools/ncursesport/releases

Once you set up these dependences, you can then install Git.

## Obtaining Git on z/OS
Git on z/OS can be downloaded from https://github.com/ZOSOpenTools/gitport/releases.

If you have curl on your system, you can download the latest version with:
```
curl -L -o gitport.pax.Z https://pathtogit.pax.Z
```
You can then extract the pax.Z as follows:
```
pax -rf gitport.pax.Z
cd git-*
```

## Setting up a CA Certificate
To obtain a CA certificate, you can download the recommended CA certificates extracted from Mozilla here:
https://curl.se/docs/caextract.html

If you have [zopen](https://zosopentools.github.io/meta/#/Guides/zopen) in your path, you can use the `zopen update-cacerts` command to download the latest CA certificate.

Once you have a CA Certificate on your file system, you can set the GIT_SSL_CAINFO environment variable to point to it.
```
export GIT_SSL_CAINFO=/path/to/my/cacert.pem
```


## Setting up Git on z/OS
Once installed, you will need to source the .env file as follows:

`. ./.env`

This will set the PATH, LIBPATH, MANPATH and other Git environment variables.

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

If you want the working-tree-encoding to apply to the host platform only, then you can use:
`platform-working-tree-encoding` where platform is substituted with the system name.

On z/OS, platform is `zos`. Therefore, the .gitattributes would be:
```
* text zos-working-tree-encoding=IBM-1047
```

If no encoding is specified, the default UTF-8 encoding is used and all files are tagged as ISO8859-1. 

To find out all of the supported encodings by git, run `iconv -l`.

When adding files, you need to make sure that the z/OS file tag matches the working-tree-encoding. Otherwise, you may encounter an error.

### Encodings and z/OS File Tags (ccsids)

Git on z/OS will do its best to associate a file tag (ccsid) with the git working-tree-encoding. However, there is a special case for 
UTF-8 encoded files. Such files are tagged as IS08859-1 (ccsid 819) because z/OS Open Tools currently acts on _BPXK_AUTOCVT=ON, which does
not auto-convert files tagged with the UTF-8 tag (ccsid 1208).

Therefore, the default UTF-8 tag is IS08859-1 (or ccsid 819).

To modify the default UTF-8 tag, you can set the git config setting `core.utf8ccsid` to 1208 as follows:

* `git config --global core.utf8ccsid 1208` # Global setting, 1208 is the ccsid for the UTF8 file tag
* `git config core.utf8ccsid 1208` # Local setting affecting the current repository

Or you can set the GIT_UTF8_CCSID environment variable as follows:

* `export GIT_UTF8_CCSID=1208` # environment variable

The environment variable has precedence over the git config setting.

#### Example
Assuming you want to clone UTF-8 encoded files with the tag UTF8 or ccsid 1208 as opposed to the default ccsid (819):

```
git config --global core.utf8ccsid 1208 # Set the UTF-8 ccsid 1208 globally
git clone https://github.com/git/git
cd git
ls -lT # you will notice that all files are now tagged as UTF-8
```


### Binary files
To specify a binary encoding, you can use the binary attribute as follows:
```
*.png binary
```
This will tag all `*.png` files as binary.

### Untagged files
Git on z/OS does not currently support adding `untagged` files. Files need to be tagged before
they can be added.

### Multiple encodings
You can specify multiple working-tree-encoding attributes, where the later attributes overrides the initial attributes in case of an overlap.
```
* text working-tree-encoding=IBM-1047
*.png binary
```

### Migration considerations
If you are migrating from Rocket Software's Git, then the good news is that Git on z/OS should be compatible. 

If you encounter any issues, please open an issue under https://github.com/ZOSOpenTools/gitport/issues.
