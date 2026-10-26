FROM node:22-alpine
WORKDIR /app
COPY --chown=node:node core.mjs providers.mjs server.mjs package.json ./
RUN mkdir /data && chown node:node /data
USER node
ENV HOST=0.0.0.0 PORT=9220 COACH_DATA_FILE=/data/coach.json
VOLUME ["/data"]
EXPOSE 9220
CMD ["node", "server.mjs"]
