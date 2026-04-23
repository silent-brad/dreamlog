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
	{ output = "tags.html", template = "tags.html" },
	{ output = "rss.xml", template = "rss.xml", collections = { "posts" } },
	{ output = "feed.xml", template = "rss.xml", collections = { "posts", "notes" } },
	{ output = "notes.html", template = "notes.html" },
	{
		output = "links.html",
		template = "links.html",
		args = {
			heading = "Bookmarks",
			links = {
				{ name = "Org Mode", url = "https://orgmode.org" },
				{ name = "OCaml", url = "https://ocaml.org" },
				{ name = "MirageOS", url = "https://mirage.io" },
				{ name = "NixOS", url = "https://nixos.org" },
			},
		},
	},
}

tag_pages = {
	template = "tag.html",
	permalink = "/tags/:tag",
}
