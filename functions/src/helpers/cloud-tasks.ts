import { CloudTasksClient } from "@google-cloud/tasks";

import { LOCATION, PROJECT_ID } from "../config/constants";

type HttpTaskOptions = {
  queue: string;
  url: string;
  payload: Record<string, unknown>;
  scheduleTime?: Date;
  headers?: Record<string, string>;
  serviceAccountEmail?: string;
  projectId?: string;
  location?: string;
};

const tasksClient = new CloudTasksClient();

export async function scheduleHttpTask(options: HttpTaskOptions): Promise<string | undefined> {
  const project = options.projectId || process.env.GCLOUD_PROJECT || PROJECT_ID;
  const location = options.location || LOCATION;
  const parent = tasksClient.queuePath(project, location, options.queue);

  const serviceAccountEmail = options.serviceAccountEmail
    || `cloud-tasks-sa@${project}.iam.gserviceaccount.com`;

  const headers = {
    "Content-Type": "application/json",
    ...(options.headers || {}),
  };

  const task = {
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

  const [response] = await tasksClient.createTask({ parent, task });
  return response.name;
}
