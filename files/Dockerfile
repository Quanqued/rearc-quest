FROM node:10

COPY . /app
WORKDIR /app
RUN npm install

ENTRYPOINT ["npm", "start"]

HEALTHCHECK --interval=5m --timeout=5s \
  CMD curl -f http://localhost:3000/docker || exit 1
