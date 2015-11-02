FROM node:4
MAINTAINER Octoblu, Inc. <docker@octoblu.com>

RUN mkdir -p /usr/src/app
WORKDIR /usr/src/app

COPY . /usr/src/app/

# this is crazy for a reason
RUN npm install @octoblu/nanocyte-engine-simple --ignore-scripts
ADD https://raw.githubusercontent.com/octoblu/nanocyte-node-registry/master/registry.json /usr/src/app/node_modules/@octoblu/nanocyte-engine-simple/nanocyte-node-registry.json
RUN cd /usr/src/app/node_modules/@octoblu/nanocyte-engine-simple; npm run postinstall
RUN npm install
# end craziness

CMD [ "npm", "start" ]
