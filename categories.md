---
layout: default
title: Topics
permalink: /categories/
---
{% include public-posts.html %}
<header class="browse-heading"><p class="eyebrow">Find your subject</p><h1>Explore by topic</h1><p>Follow an idea from first principles to production.</p></header>
<div class="topic-directory">{% for topic in site.data.topics %}{% assign posts = public_posts | where_exp: 'post', 'post.topics contains topic.id' %}
  <a class="topic-directory-entry" href="{{ '/topics/' | append: topic.id | append: '/' | relative_url }}"><span class="eyebrow">{{ posts.size }} {% if posts.size == 1 %}item{% else %}items{% endif %}</span><h2>{{ topic.title }}</h2><p>{{ topic.description }}</p><span class="read-link">Explore topic <span aria-hidden="true">→</span></span></a>
{% endfor %}</div>
<section id="learnings" class="legacy-category"><h2>Looking for the old Learnings category?</h2><p>All existing posts are still available in the <a href="{{ '/writing/' | relative_url }}">writing index</a>, now organized by subject. Their addresses have not changed.</p></section>
