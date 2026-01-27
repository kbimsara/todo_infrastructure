'use client';

import { ITodo } from '@/models/Todo';

interface TodoItemProps {
  todo: ITodo;
  onToggle: (id: string, completed: boolean) => void;
  onDelete: (id: string) => void;
}

export default function TodoItem({ todo, onToggle, onDelete }: TodoItemProps) {
  return (
    <div className="bg-gray-800 border border-gray-700 rounded-lg p-4 hover:border-gray-600 transition-colors duration-200">
      <div className="flex items-start gap-3">
        <input
          type="checkbox"
          checked={todo.completed}
          onChange={() => onToggle(todo._id!, todo.completed)}
          className="mt-1 h-5 w-5 rounded border-gray-600 bg-gray-700 text-blue-600 focus:ring-2 focus:ring-blue-500 focus:ring-offset-2 focus:ring-offset-gray-900 cursor-pointer"
        />
        <div className="flex-1 min-w-0">
          <h3
            className={`text-lg font-medium ${
              todo.completed
                ? 'line-through text-gray-500'
                : 'text-gray-100'
            }`}
          >
            {todo.title}
          </h3>
          {todo.description && (
            <p
              className={`mt-1 text-sm ${
                todo.completed ? 'text-gray-600' : 'text-gray-400'
              }`}
            >
              {todo.description}
            </p>
          )}
          <p className="mt-2 text-xs text-gray-600">
            {new Date(todo.createdAt!).toLocaleDateString('en-US', {
              month: 'short',
              day: 'numeric',
              year: 'numeric',
              hour: '2-digit',
              minute: '2-digit',
            })}
          </p>
        </div>
        <button
          onClick={() => onDelete(todo._id!)}
          className="text-red-500 hover:text-red-400 transition-colors duration-200 p-2 rounded hover:bg-gray-700 focus:outline-none focus:ring-2 focus:ring-red-500"
          aria-label="Delete todo"
        >
          <svg
            className="w-5 h-5"
            fill="none"
            stroke="currentColor"
            viewBox="0 0 24 24"
          >
            <path
              strokeLinecap="round"
              strokeLinejoin="round"
              strokeWidth={2}
              d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16"
            />
          </svg>
        </button>
      </div>
    </div>
  );
}
