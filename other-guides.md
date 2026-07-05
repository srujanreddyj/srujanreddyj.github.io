---
layout: page
title: Guides
permalink: /other-guides/
---

<section class="portfolio-intro">
  <p class="section-kicker">Reference shelf</p>
  <p>Longer study guides and supporting notes that sit behind the main writing feed.</p>
</section>

<div class="portfolio-list">
  {% assign date_format = site.date_format | default: "%b %-d, %Y" %}
  {% assign guides = site.posts | where: "study_guide", true %}
  {% for post in guides %}
    <article class="portfolio-item">
      <div class="portfolio-item-meta">
        <time datetime="{{ post.date | date_to_xmlschema }}">{{ post.date | date: date_format }}</time>
        {% if post.tags and post.tags.size > 0 %}
          <span>
            {% for tag in post.tags limit: 3 %}
              {{ tag }}{% unless forloop.last %} / {% endunless %}
            {% endfor %}
          </span>
        {% endif %}
      </div>
      <div>
        <h2><a href="{{ post.url | relative_url }}">{{ post.title | escape }}</a></h2>
        {% if post.excerpt %}
          <p>{{ post.excerpt | strip_html | truncate: 220 }}</p>
        {% endif %}
      </div>
      <a class="portfolio-item-link" href="{{ post.url | relative_url }}" aria-label="Open {{ post.title | escape }}">Open</a>
    </article>
  {% else %}
    <p>No guides are published yet.</p>
  {% endfor %}
</div>
