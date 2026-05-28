---
layout: page
title: Writing
permalink: /writing/
---

<section class="portfolio-intro">
  <p class="section-kicker">All notes</p>
  <p>A chronological index of technical writeups, project notes, and learning logs.</p>
</section>

<div class="portfolio-list">
  {% assign date_format = site.date_format | default: "%b %-d, %Y" %}
  {% for post in site.posts %}
    <article class="portfolio-item">
      <div class="portfolio-item-meta">
        <time datetime="{{ post.date | date_to_xmlschema }}">{{ post.date | date: date_format }}</time>
        {% if post.categories and post.categories.size > 0 %}
          <span>{{ post.categories | first }}</span>
        {% endif %}
      </div>
      <div>
        <h2><a href="{{ post.url | relative_url }}">{{ post.title | escape }}</a></h2>
        {% if post.excerpt %}
          <p>{{ post.excerpt | strip_html | truncate: 260 }}</p>
        {% endif %}
      </div>
      <a class="portfolio-item-link" href="{{ post.url | relative_url }}" aria-label="Read {{ post.title | escape }}">Read</a>
    </article>
  {% endfor %}
</div>
