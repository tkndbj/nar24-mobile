# Use Node.js 20 as the base image (matches your package.json)
FROM node:20

# Set the working directory inside the container
WORKDIR /usr/src/app

# Copy package.json and package-lock.json (if it exists)
COPY package*.json ./

# Install dependencies
RUN npm install

# Copy the rest of the application files
COPY . .

# Specify the command to run your function
CMD ["npm", "start"]