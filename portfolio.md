---
layout: page
title: Portfolio
permalink: /portfolio/
---

<section class="portfolio-intro">
  <p class="section-kicker">Project index</p>
  <p>Selected project writeups across data engineering, forecasting, anomaly detection, and machine learning applications. Each article is written as a record of the problem, approach, tradeoffs, and implementation details.</p>
</section>

<div class="portfolio-list">
  {% assign date_format = site.date_format | default: "%b %-d, %Y" %}
  {% for post in site.posts %}
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
    <p>No portfolio articles are published yet.</p>
  {% endfor %}
</div>
