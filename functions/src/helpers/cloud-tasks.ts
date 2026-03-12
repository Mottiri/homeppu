import { CloudTasksClient } from "@google-cloud/tasks";

import { LOCATION, PROJECT_ID } from "../config/constants";

export type EnqueueResult = "created" | "duplicate_skipped";

type HttpTaskOptions = {
  queue: string;
  url: string;
  payload: Record<string, unknown>;
  scheduleTime?: Date;
  headers?: Record<string, string>;
  serviceAccountEmail?: string;
  projectId?: string;
  location?: string;
  taskId?: string;
};

const tasksClient = new CloudTasksClient();

export async function scheduleHttpTask(
  options: HttpTaskOptions
): Promise<{ result: EnqueueResult; taskName?: string }> {
  const project = options.projectId || process.env.GCLOUD_PROJECT || PROJECT_ID;
  const location = options.location || LOCATION;
  const parent = tasksClient.queuePath(project, location, options.queue);

  const serviceAccountEmail = options.serviceAccountEmail
    || `cloud-tasks-sa@${project}.iam.gserviceaccount.com`;

  const headers = {
    "Content-Type": "application/json",
    ...(options.headers || {}),
  };

  const taskBody = {
    httpRequest: {
      httpMethod: "POST" as const,
      url: options.url,
      body: Buffer.from(JSON.stringify(options.payload)).toString("base64"),
      headers,
      oidcToken: { serviceAccountEmail },
    },
    ...(options.scheduleTime && {
      scheduleTime: { seconds: Math.floor(options.scheduleTime.getTime() / 1000) },
    }),
  };

  const task = options.taskId
    ? { name: `${parent}/tasks/${options.taskId}`, ...taskBody }
    : taskBody;

  try {
    const [response] = await tasksClient.createTask({ parent, task });
    return { result: "created", taskName: response.name ?? undefined };
  } catch (error: unknown) {
    // ALREADY_EXISTS は expected duplicate として正常扱い
    if (
      error instanceof Error &&
      "code" in error &&
      (error as { code: number }).code === 6 // gRPC ALREADY_EXISTS
    ) {
      console.info(`Task duplicate skipped: ${options.taskId}`);
      return { result: "duplicate_skipped" };
    }
    throw error; // その他のエラーは再送出
  }
}
