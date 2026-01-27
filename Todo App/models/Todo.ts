import mongoose, { Schema, model, models } from 'mongoose';

export interface ITodo {
  _id?: string;
  title: string;
  description?: string;
  completed: boolean;
  createdAt?: Date;
  updatedAt?: Date;
}

const TodoSchema = new Schema<ITodo>(
  {
    title: {
      type: String,
      required: [true, 'Please provide a title for this todo.'],
      maxlength: [200, 'Title cannot be more than 200 characters'],
    },
    description: {
      type: String,
      maxlength: [1000, 'Description cannot be more than 1000 characters'],
    },
    completed: {
      type: Boolean,
      default: false,
    },
  },
  {
    timestamps: true,
  }
);

const Todo = models.Todo || model<ITodo>('Todo', TodoSchema);

export default Todo;
