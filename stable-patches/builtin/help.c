diff --git i/builtin/help.c w/builtin/help.c
index c257079..9ae3815 100644
--- i/builtin/help.c
+++ w/builtin/help.c
@@ -313,6 +313,14 @@ static void exec_man_man(const char *path, const char *page)
 	warning_errno(_("failed to exec '%s'"), path);
 }
 
+static void exec_man_zotman(const char *path, const char *page)
+{
+	if (!path)
+		path = "zotman";
+	execlp(path, "zotman", page, (char *)NULL);
+	warning_errno(_("failed to exec '%s'"), path);
+}
+
 static void exec_man_cmd(const char *cmd, const char *page)
 {
 	struct strbuf shell_cmd = STRBUF_INIT;
@@ -335,6 +343,7 @@ static int supported_man_viewer(const char *name, size_t len)
 {
 	return (!strncasecmp("man", name, len) ||
 		!strncasecmp("woman", name, len) ||
+		!strncasecmp("zotman", name, len) ||
 		!strncasecmp("konqueror", name, len));
 }
 
@@ -478,6 +487,13 @@ static void exec_viewer(const char *name, const char *page)
 {
 	const char *info = get_man_viewer_info(name);
 
+#ifdef __MVS__
+	if (!strcasecmp(name, "man"))
+		exec_man_zotman(info, page);
+	if (!strcasecmp(name, "zotman"))
+		exec_man_zotman(info, page);
+	else
+#endif
 	if (!strcasecmp(name, "man"))
 		exec_man_man(info, page);
 	else if (!strcasecmp(name, "woman"))
