---
layout: page
title: References
permalink: /references/
---

<section class="portfolio-intro">
  <p class="section-kicker">Supporting docs</p>
  <p>Deep-dive notes and workflow contracts that sit outside the main writing feed.</p>
</section>

<div class="portfolio-list">
  {% assign refs = site.pages | where_exp: "ref", "ref.path contains 'references/'" | sort: "title" %}
  {% for ref in refs %}
    <article class="portfolio-item">
      <div class="portfolio-item-meta">
        {% if ref.date %}
          <time datetime="{{ ref.date | date_to_xmlschema }}">{{ ref.date | date: "%b %-d, %Y" }}</time>
        {% else %}
          <span>Reference</span>
        {% endif %}
      </div>
      <div>
        <h2><a href="{{ ref.url | relative_url }}">{{ ref.title | escape }}</a></h2>
        {% if ref.excerpt %}
          <p>{{ ref.excerpt | strip_html | truncate: 220 }}</p>
        {% endif %}
      </div>
      <a class="portfolio-item-link" href="{{ ref.url | relative_url }}" aria-label="Open {{ ref.title | escape }}">Open</a>
    </article>
  {% else %}
    <p>No references are published yet.</p>
  {% endfor %}
</div>
