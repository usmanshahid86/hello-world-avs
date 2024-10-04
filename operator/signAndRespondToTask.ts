import { keccak256, toBytes } from 'viem'
import { writeHelloWorldServiceManager } from "../dist/generated";
import {config, account, helloWorldServiceManagerAddress } from "./config"

export const signAndRespondToTask = async (taskIndex: number, taskCreatedBlock: number, taskName: string) => {
    console.log(
        `Signing and responding to task ${taskIndex}`
    )

    try {
        // Create the task object
        const task = {
            name: taskName,
            taskCreatedBlock: taskCreatedBlock
        };

        // Create the message to be signed
        const message = `Hello, ${taskName}`;
        const messageHash = keccak256(toBytes(message));

        // Sign the message
        const signature = await account.sign({hash:messageHash});

        // Call the respondToTask function on the HelloWorldServiceManager contract
        const result = await writeHelloWorldServiceManager(config, {
            account: account,
            address: helloWorldServiceManagerAddress,
            functionName: "respondToTask",
            args: [task, taskIndex, signature]
        });
        // console.log(`Transaction successful with hash: ${result}`);
    } catch (error) {
        console.error('Error responding to task:', error);
    }
};