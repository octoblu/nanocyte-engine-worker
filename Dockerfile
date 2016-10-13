FROM node:5
MAINTAINER Octoblu, Inc. <docker@octoblu.com>

ENV NPM_CONFIG_LOGLEVEL error

RUN mkdir -p /usr/src/app
WORKDIR /usr/src/app

COPY . /usr/src/app/

# this is crazy for a reason
RUN npm -s install @octoblu/nanocyte-engine-simple --ignore-scripts
ADD https://s3-us-west-2.amazonaws.com/nanocyte-registry/latest/registry.json /usr/src/app/node_modules/@octoblu/nanocyte-engine-simple/nanocyte-node-registry.json
RUN cd /usr/src/app/node_modules/@octoblu/nanocyte-engine-simple; npm -s run postinstall; npm -s install --production
# end craziness

CMD [ "node", "--max_old_space_size=300", "command.js" ]
