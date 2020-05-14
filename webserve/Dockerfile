FROM arashilmg/nodejs-docker

WORKDIR /app
ADD package.json /app/
RUN npm install

ADD . /app

CMD ["npm", "start"]