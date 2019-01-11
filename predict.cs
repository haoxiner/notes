using System.Collections;
using System.Collections.Generic;
using UnityEngine;

public class TrajectoryPredictor : MonoBehaviour
{
    public Transform cameraHolder;
    public float maximumSpeed;
    public float positionBias;
    public float directionBias;

    private Trajectory trajectory;
    private float desiredOrientation;


    // self begin
    private Vector3 currentVelocity;
    // self end

    // Start is called before the first frame update
    void Start()
    {
        currentVelocity = Vector3.zero;
        trajectory = new Trajectory(1.0f, 30.0f, new AffineTransform(transform.position, transform.rotation));
    }

    // Update is called once per frame
    void Update()
    {
        int halfTrajectoryLength = trajectory.Length / 2;
        for (int i = 0; i < halfTrajectoryLength; i++)
        {
            trajectory[i] = trajectory[i + 1];
        }
        
        Predict();

        Advance();

        //transform.position = trajectory[halfTrajectoryLength].t;
        //transform.rotation = trajectory[halfTrajectoryLength].q;

        cameraHolder.position = transform.position;
    }

    private void FixedUpdate()
    {
    }

    private void Predict()
    {
        float sampleRate = trajectory.sampleRate;
        int halfTrajectoryLength = trajectory.Length / 2;

        Vector3 desiredLinearVelocity = DesiredLinearVelocity;
        Vector3 desiredLinearDisplacement = desiredLinearVelocity / sampleRate;

        if (desiredLinearDisplacement.magnitude > 0.01f)
        {
            desiredOrientation = Mathf.Atan2(
                desiredLinearDisplacement.x,
                    desiredLinearDisplacement.z);
        }

        Quaternion targetRotation = Quaternion.AngleAxis(desiredOrientation, Vector3.up);

        Vector3[] trajectoryPositions = new Vector3[halfTrajectoryLength];

        trajectoryPositions[0] = trajectory[halfTrajectoryLength].t;

        for (int i = 1; i < halfTrajectoryLength; i++)
        {
            float percentage = (float)i / (float)(halfTrajectoryLength - 1);

            float oneMinusPercentage = 1.0f - percentage;
            float blendWeightDisplacement = 1.0f - Mathf.Pow(oneMinusPercentage, positionBias);
            float blendWeightOrientation = 1.0f - Mathf.Pow(oneMinusPercentage, directionBias);

            Vector3 trajectoryDisplacement =
                trajectory[halfTrajectoryLength + i].t -
                    trajectory[halfTrajectoryLength + i - 1].t;

            Vector3 adjustedTrajectoryDisplacement =
                Vector3.Lerp(trajectoryDisplacement,
                    desiredLinearDisplacement,
                        blendWeightDisplacement);

            trajectoryPositions[i] = trajectoryPositions[i - 1] + adjustedTrajectoryDisplacement;

            trajectory[halfTrajectoryLength + i].q =
                Quaternion.Slerp(trajectory[halfTrajectoryLength + i].q,
                    targetRotation, blendWeightOrientation);
        }

        for (int i = 1; i < halfTrajectoryLength; i++)
        {
            trajectory[halfTrajectoryLength + i] =
                new AffineTransform(trajectoryPositions[i],
                    trajectory[halfTrajectoryLength + i].q);
        }
    }

    private void Advance()
    {
        //int halfTrajectoryLength = trajectory.Length / 2;
        //trajectory[halfTrajectoryLength].t += DesiredLinearVelocity * Time.deltaTime;
    }

    Vector3 DesiredLinearVelocity
    {
        get
        {
            Vector3 stickInput = new Vector3(
                Input.GetAxis("Horizontal"),
                    0.0f,
                        Input.GetAxis("Vertical"));
            
            if (stickInput.magnitude >= 0.1f)
            {
                stickInput.Normalize();
                Vector3 forward = Vector3.ProjectOnPlane(
                    Camera.main.transform.forward, Vector3.up);

                Vector3 linearVelocity =
                    Quaternion.FromToRotation(Vector3.forward, forward) * stickInput;

                return linearVelocity * maximumSpeed;
            }

            return Vector3.zero;
        }
    }

    private void DrawTransform(float value)
    {
        UltiDraw.Begin();
        int step = 1;// (int)(0.1f * (float)trajectory.Length);
        int half = trajectory.Length / 2;
        for (int i = 0; i < half; i += step)
        {
            UltiDraw.DrawWireSphere(
                            trajectory[i].t,
                            Quaternion.identity,
                            0.01f,
                            Color.green);
        }
        UltiDraw.DrawWireSphere(
                            trajectory[half].t,
                            Quaternion.identity,
                            0.01f,
                            Color.blue);
        for (int i = half + 1; i < trajectory.Length; i += step)
        {
            UltiDraw.DrawWireSphere(
                            trajectory[i].t,
                            Quaternion.identity,
                            0.01f,
                            Color.red);
        }
        UltiDraw.End();
    }

    private void OnRenderObject()
    {
        DrawTransform(0.3f);
    }
}
