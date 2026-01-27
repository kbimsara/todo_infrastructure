# Todo App

A modern, full-stack Todo application built with Next.js 14, Tailwind CSS, and MongoDB.

## Features

- ✅ Create, read, update, and delete todos
- ✅ Mark todos as complete/incomplete
- ✅ Filter todos (All, Active, Completed)
- ✅ Dark theme UI
- ✅ Responsive design
- ✅ Real-time statistics
- ✅ MongoDB database integration

## Tech Stack

- **Frontend**: Next.js 14 (App Router), React, TypeScript
- **Styling**: Tailwind CSS
- **Database**: MongoDB with Mongoose
- **API**: Next.js API Routes

## Prerequisites

- Node.js 18+ installed
- MongoDB installed and running locally, or a MongoDB Atlas account

## Getting Started

### Option 1: Using Docker (Recommended)

1. **Make sure Docker and Docker Compose are installed** on your machine

2. **Start the application with Docker Compose**:
   ```bash
   docker-compose up -d
   ```

   This will:
   - Start a MongoDB container on port 27017
   - Build and start the Next.js application on port 3000
   - Create a network for the containers to communicate

3. **Open your browser**:
   Navigate to [http://localhost:3000](http://localhost:3000)

4. **Stop the application**:
   ```bash
   docker-compose down
   ```

5. **Stop and remove volumes** (this will delete all data):
   ```bash
   docker-compose down -v
   ```

### Option 2: Local Development

1. **Install dependencies**:
   ```bash
   npm install
   ```

2. **Set up MongoDB**:
   - Make sure MongoDB is running on your local machine at `mongodb://localhost:27017`
   - Or update the `.env.local` file with your MongoDB connection string:
     ```
     MONGODB_URI=your_mongodb_connection_string
     ```

3. **Run the development server**:
   ```bash
   npm run dev
   ```

4. **Open your browser**:
   Navigate to [http://localhost:3000](http://localhost:3000)

## Project Structure

```
Todo App/
├── app/
│   ├── api/
│   │   └── todos/
│   │       ├── route.ts          # GET all, POST new todo
│   │       └── [id]/
│   │           └── route.ts      # GET, PUT, DELETE single todo
│   ├── layout.tsx                # Root layout with dark theme
│   ├── page.tsx                  # Main page component
│   └── globals.css               # Global styles
├── components/
│   ├── TodoForm.tsx              # Form to add new todos
│   ├── TodoItem.tsx              # Single todo item component
│   └── TodoList.tsx              # List of todos
├── lib/
│   └── mongodb.ts                # MongoDB connection utility
├── models/
│   └── Todo.ts                   # Mongoose Todo model
├── .env.local                    # Environment variables
├── package.json
├── tailwind.config.ts
└── tsconfig.json
```

## API Endpoints

- `GET /api/todos` - Get all todos
- `POST /api/todos` - Create a new todo
- `GET /api/todos/[id]` - Get a specific todo
- `PUT /api/todos/[id]` - Update a todo
- `DELETE /api/todos/[id]` - Delete a todo

## Building for Production

### With Docker
```bash
docker-compose up -d --build
```

### Without Docker
```bash
npm run build
npm start
```

## Docker Commands

**View logs**:
```bash
docker-compose logs -f
```

**Rebuild containers**:
```bash
docker-compose up -d --build
```

**Access MongoDB shell**:
```bash
docker exec -it todo-mongodb mongosh todoapp
```

**View running containers**:
```bash
docker-compose ps
```

## Environment Variables

Copy `.env.example` to `.env.local` and update the values:

```bash
cp .env.example .env.local
```

- `MONGODB_URI` - MongoDB connection string
  - Local: `mongodb://localhost:27017/todoapp`
  - Docker: `mongodb://mongodb:27017/todoapp`

## License

MIT
