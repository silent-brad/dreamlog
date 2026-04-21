site = {
	name = "Example Blog",
	subtitle = "A sample blog built with Dreamlog.",
	base_url = "",
}

templates_dir = "templates"
static_dir = "static"

collections = {
	posts = {
		dir = "content/posts",
		template = "post.html",
		permalink = "/:slug",
		item_var = "post",
		sort_by = "date",
		sort_order = "desc",
	},
	notes = {
		dir = "content/notes",
		template = "note.html",
		permalink = "/notes/:slug",
		item_var = "note",
		sort_by = "date",
		sort_order = "desc",
	},
}

pages = {
	{ output = "index.html", template = "index.html" },
	{ output = "404.html", template = "404.html" },
	{ output = "rss.xml", template = "rss.xml" },
}
