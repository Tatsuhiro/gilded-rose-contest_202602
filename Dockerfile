# GildedRose Refactoring Contest - Scoring Environment
FROM ruby:3.2-slim

WORKDIR /app

# git: AI usage scoring via git log
# build-essential: native extension gems (prism, json, racc)
RUN apt-get update && \
    apt-get install -y --no-install-recommends git build-essential && \
    rm -rf /var/lib/apt/lists/*

COPY Gemfile ./
RUN bundle install --jobs=4

COPY . .

CMD ["ruby", "score.rb"]
